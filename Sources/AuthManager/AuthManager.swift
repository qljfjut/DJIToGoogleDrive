// ====================================
// 📁 文件职责：Google OAuth 2.0 PKCE 鉴权与双轨安全持久化中心
// 包含：PKCE 挑战码派生、RFC 3986 标准参数编码、本地 127.0.0.1 回调捕获、Token 自动轮转、0600 本地安全配置双轨持久化
// 不包含：媒体文件切片与扫描
// 依赖：Foundation, Security, CryptoKit, AppKit
// ====================================

import Foundation
import Security
import CryptoKit
import AppKit

public enum AuthError: LocalizedError, Sendable {
    case missingClientCredentials
    case invalidAuthorizationURL
    case listenerFailed
    case userCancelled
    case tokenExchangeFailed(String)
    case notAuthenticated
    
    public var errorDescription: String? {
        switch self {
        case .missingClientCredentials:
            return "尚未配置 Google Cloud Client ID 或 Client Secret，请前往设置配置。"
        case .invalidAuthorizationURL:
            return "无法构建合法的 OAuth 授权请求链接。"
        case .listenerFailed:
            return "启动本地 127.0.0.1 授权回调监听失败，端口可能被占用。"
        case .userCancelled:
            return "用户已取消网页端授权。"
        case .tokenExchangeFailed(let msg):
            return "通过授权码换取 Token 失败: \(msg)"
        case .notAuthenticated:
            return "尚未登录 Google 账号，请在控制台先点击授权登录。"
        }
    }
}

/// 本地安全隔离持久化模型（权限严格锁定 0600，杜绝签名失效导致凭据丢失）
private struct AuthConfig: Codable {
    var clientId: String?
    var clientSecret: String?
    var accessToken: String?
    var refreshToken: String?
    var tokenExpiry: String?
    var userEmail: String?
}

@MainActor
public final class AuthManager: ObservableObject {
    public static let shared = AuthManager()
    
    private static let redirectPort: UInt16 = 8085
    private static let redirectURI = "http://127.0.0.1:8085/oauth/callback"
    private static let scope = "https://www.googleapis.com/auth/drive.file"
    
    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var hasClientCredentials: Bool = false
    @Published public private(set) var userEmail: String?
    
    private let storageURL: URL
    private var config: AuthConfig = AuthConfig()
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DJIToDrive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("auth.json")
        
        loadConfig()
        checkCredentialsStatus()
    }
    
    // MARK: - 状态检查 (Status Checking)
    
    public func checkCredentialsStatus() {
        let hasId = getSecureItem(key: "client_id") != nil
        let hasSecret = getSecureItem(key: "client_secret") != nil
        self.hasClientCredentials = (hasId && hasSecret)
        
        let hasToken = getSecureItem(key: "refresh_token") != nil || getSecureItem(key: "access_token") != nil
        self.isAuthenticated = hasToken
        self.userEmail = getSecureItem(key: "user_email")
    }
    
    // MARK: - 凭据录入与保存 (Save Client ID / Secret)
    
    public func saveClientCredentials(clientId: String, clientSecret: String) {
        setSecureItem(key: "client_id", value: clientId.trimmingCharacters(in: .whitespacesAndNewlines))
        setSecureItem(key: "client_secret", value: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        checkCredentialsStatus()
    }
    
    public func getClientId() -> String? {
        getSecureItem(key: "client_id")
    }
    
    public func getClientSecret() -> String? {
        getSecureItem(key: "client_secret")
    }
    
    public func signOut() {
        deleteSecureItem(key: "access_token")
        deleteSecureItem(key: "refresh_token")
        deleteSecureItem(key: "token_expiry")
        deleteSecureItem(key: "user_email")
        checkCredentialsStatus()
    }
    
    // MARK: - PKCE 授权启动流水线 (OAuth 2.0 PKCE Flow)
    
    public func startAuthorization() async throws {
        guard let clientId = getClientId(), let clientSecret = getClientSecret(), !clientId.isEmpty, !clientSecret.isEmpty else {
            throw AuthError.missingClientCredentials
        }
        
        // 1. 生成高熵 Code Verifier 与 SHA-256 Code Challenge
        let verifier = generateRandomCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        
        // 2. 构造网页授权请求 URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = components.url else {
            throw AuthError.invalidAuthorizationURL
        }
        
        // 3. 打开系统默认浏览器进入 Google 官方授权页
        NSWorkspace.shared.open(authURL)
        
        // 4. 本地启动临时监听捕获重定向授权码 (Code)
        let authCode = try await captureAuthorizationCode()
        
        // 5. 用授权码向 Google Token 端点换取 Token
        try await exchangeCodeForTokens(code: authCode, verifier: verifier, clientId: clientId, clientSecret: clientSecret)
        
        checkCredentialsStatus()
    }
    
    // MARK: - 换取与刷新 Token (Exchange & Refresh)
    
    private func exchangeCodeForTokens(code: String, verifier: String, clientId: String, clientSecret: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params: [String: String] = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": Self.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        
        let bodyString = params.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AuthError.tokenExchangeFailed(errorText)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let accessToken = json["access_token"] as? String {
                setSecureItem(key: "access_token", value: accessToken)
            }
            if let refreshToken = json["refresh_token"] as? String {
                setSecureItem(key: "refresh_token", value: refreshToken)
            }
            if let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? json["expires_in"] as? Double {
                let expiryDate = Date().addingTimeInterval(expiresIn)
                setSecureItem(key: "token_expiry", value: "\(expiryDate.timeIntervalSince1970)")
            }
        }
    }
    
    /// 获取当前可用的 Access Token（终生免维护：若过期则自动后台毫秒级静默换取新 Token）
    public func getValidAccessToken() async throws -> String {
        if let expiryStr = getSecureItem(key: "token_expiry"),
           let expiryTime = Double(expiryStr),
           let accessToken = getSecureItem(key: "access_token") {
            // 如果还有超过 60 秒有效期，直接复用
            if Date().timeIntervalSince1970 < (expiryTime - 60) {
                return accessToken
            }
        }
        
        // 尝试通过 refresh_token 静默刷新
        guard let refreshToken = getSecureItem(key: "refresh_token"),
              let clientId = getClientId(),
              let clientSecret = getClientSecret() else {
            throw AuthError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params: [String: String] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        let bodyString = params.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.notAuthenticated
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let newAccessToken = json["access_token"] as? String {
            setSecureItem(key: "access_token", value: newAccessToken)
            if let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? json["expires_in"] as? Double {
                let expiryDate = Date().addingTimeInterval(expiresIn)
                setSecureItem(key: "token_expiry", value: "\(expiryDate.timeIntervalSince1970)")
            }
            return newAccessToken
        }
        
        throw AuthError.notAuthenticated
    }
    
    // MARK: - 本地 Loopback 监听器 (Local Redirect Listener)
    
    private func captureAuthorizationCode() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let serverFd = socket(AF_INET, SOCK_STREAM, 0)
                guard serverFd >= 0 else {
                    continuation.resume(throwing: AuthError.listenerFailed)
                    return
                }
                
                var optVal: Int32 = 1
                setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &optVal, socklen_t(MemoryLayout<Int32>.size))
                
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(Self.redirectPort).bigEndian
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                
                let bindRes = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                
                guard bindRes == 0, listen(serverFd, 1) == 0 else {
                    close(serverFd)
                    continuation.resume(throwing: AuthError.listenerFailed)
                    return
                }
                
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(serverFd, $0, &clientLen)
                    }
                }
                
                guard clientFd >= 0 else {
                    close(serverFd)
                    continuation.resume(throwing: AuthError.listenerFailed)
                    return
                }
                
                var buffer = [CChar](repeating: 0, count: 4096)
                let bytesRead = read(clientFd, &buffer, buffer.count - 1)
                
                var capturedCode: String?
                if bytesRead > 0 {
                    let requestText = String(cString: buffer)
                    if let codeRange = requestText.range(of: "code=") {
                        let sub = requestText[codeRange.upperBound...]
                        // 遇到空格或 & 即刻截断，保证无论是否包含后续参数均能精准捕获纯净授权码
                        let endChars = CharacterSet(charactersIn: " &\r\n")
                        if let endRange = sub.rangeOfCharacter(from: endChars) {
                            capturedCode = String(sub[..<endRange.lowerBound])
                        } else {
                            capturedCode = String(sub)
                        }
                    }
                }
                
                // 返回漂亮的 HTML 提示页面
                let html = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Connection: close\r
                \r
                <html>
                <body style="font-family: -apple-system, sans-serif; display:flex; justify-content:center; align-items:center; height:100vh; background:#f5f5f7;">
                    <div style="background:white; padding:36px; border-radius:16px; box-shadow:0 8px 24px rgba(0,0,0,0.08); text-align:center;">
                        <h2 style="color:#1d1d1f; margin-bottom:8px;">🎉 DJIToDrive 授权成功！</h2>
                        <p style="color:#86868b; margin:0;">已安全绑定 Google Drive，您可以关闭此浏览器标签页。</p>
                    </div>
                </body>
                </html>
                """
                
                html.withCString { ptr in
                    _ = write(clientFd, ptr, strlen(ptr))
                }
                
                close(clientFd)
                close(serverFd)
                
                if let code = capturedCode {
                    continuation.resume(returning: code)
                } else {
                    continuation.resume(throwing: AuthError.userCancelled)
                }
            }
        }
    }
    
    // MARK: - RFC 3986 标准参数编码与 PKCE Helper
    
    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
    
    private func generateRandomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .ascii) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - 本地独立安全持久化 (Secure File Storage: POSIX 0600)
    
    private func getSecureItem(key: String) -> String? {
        switch key {
        case "client_id": return config.clientId
        case "client_secret": return config.clientSecret
        case "access_token": return config.accessToken
        case "refresh_token": return config.refreshToken
        case "token_expiry": return config.tokenExpiry
        case "user_email": return config.userEmail
        default: return nil
        }
    }
    
    private func setSecureItem(key: String, value: String) {
        switch key {
        case "client_id": config.clientId = value
        case "client_secret": config.clientSecret = value
        case "access_token": config.accessToken = value
        case "refresh_token": config.refreshToken = value
        case "token_expiry": config.tokenExpiry = value
        case "user_email": config.userEmail = value
        default: break
        }
        saveConfig()
    }
    
    private func deleteSecureItem(key: String) {
        switch key {
        case "client_id": config.clientId = nil
        case "client_secret": config.clientSecret = nil
        case "access_token": config.accessToken = nil
        case "refresh_token": config.refreshToken = nil
        case "token_expiry": config.tokenExpiry = nil
        case "user_email": config.userEmail = nil
        default: break
        }
        saveConfig()
    }
    
    private func loadConfig() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode(AuthConfig.self, from: data) else {
            return
        }
        self.config = decoded
    }
    
    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: storageURL, options: .atomic)
        
        // 严格锁定文件权限为 0600（仅当前登录用户可读写，防止其他应用窥探）
        var attrs = [FileAttributeKey: Any]()
        attrs[.posixPermissions] = 0o600
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: storageURL.path)
    }
}
