// ====================================
// 📁 文件职责：Google 凭证配置向导与账号授权设置窗口
// 包含：Client ID / Secret 钥匙串录入、PKCE 一键授权触发与账号连接状态展示
// 不包含：底层分片网络传输
// 依赖：SwiftUI, AuthManager
// ====================================

import SwiftUI
import AuthManager

struct SettingsView: View {
    @ObservedObject var authManager: AuthManager = .shared
    
    @State private var clientIdInput: String = ""
    @State private var clientSecretInput: String = ""
    @State private var isSaving: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String?
    @State private var saveSuccessMessage: String?
    @State private var showSecret: Bool = false
    
    // 目标目录与过滤规则状态
    @State private var targetFolderInput: String = ""
    @State private var createDateSubfolderInput: Bool = true
    @State private var minVideoSizeMBInput: Int = 10
    @State private var targetSavedMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                Divider()
                credentialsSection
                Divider()
                authStatusSection
                Divider()
                targetDirectorySection
                Divider()
                footerHelpSection
            }
            .padding(20)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadExistingCredentials()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.title)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Drive 授权配置")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("所有凭证均通过 macOS Keychain 硬件加密安全托管")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Google Cloud 凭证配置")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Client ID:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField("例如: 123456...apps.googleusercontent.com", text: $clientIdInput)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if let pasteString = NSPasteboard.general.string(forType: .string) {
                            clientIdInput = pasteString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("从系统剪贴板一键粘贴 Client ID")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Client Secret:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    if showSecret {
                        TextField("例如: GOCSPX-...", text: $clientSecretInput)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("例如: GOCSPX-...", text: $clientSecretInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showSecret.toggle()
                    } label: {
                        Image(systemName: showSecret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                    .help(showSecret ? "隐藏密钥" : "显示明文密钥")
                    
                    Button {
                        if let pasteString = NSPasteboard.general.string(forType: .string) {
                            clientSecretInput = pasteString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("从系统剪贴板一键粘贴 Client Secret")
                }
            }
            
            HStack {
                Button("保存凭证至 Keychain") {
                    saveCredentials()
                }
                .buttonStyle(.borderedProminent)
                .disabled(clientIdInput.isEmpty || clientSecretInput.isEmpty)
                
                if let msg = saveSuccessMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
            }
        }
    }

    private var authStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. 账号授权状态")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(authManager.isAuthenticated ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(authManager.isAuthenticated ? "已成功连接 Google Drive" : "尚未授权 Google 账号")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let email = authManager.userEmail {
                        Text("当前账号: \(email)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if authManager.isAuthenticated {
                    Button("退出登录") {
                        authManager.signOut()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(isAuthenticating ? "正在打开浏览器..." : "立即登录 Google 账号") {
                        triggerOAuth()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!authManager.hasClientCredentials || isAuthenticating)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var targetDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Google Drive 目标目录与过滤规则")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("目标目录 (支持文件夹名称或直接粘贴 Google Drive 网址/ID):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("例如: DJI_Media 或粘贴 drive.google.com/drive/folders/...", text: $targetFolderInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        if let pasteString = NSPasteboard.general.string(forType: .string) {
                            targetFolderInput = pasteString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("从系统剪贴板一键粘贴文件夹链接或名称")
                }
            }
            
            Toggle("按拍摄日期创建归档子目录 (例如: 目标目录/2026-09-09/)", isOn: $createDateSubfolderInput)
                .font(.subheadline)
            
            HStack {
                Text("疑似废片过滤阈值:")
                    .font(.subheadline)
                Stepper("\(minVideoSizeMBInput) MB", value: $minVideoSizeMBInput, in: 1...100)
                    .frame(width: 140)
                Text("(小于此大小的视频标记为废片并不默认勾选)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("保存目标目录与过滤配置") {
                    saveTargetSettings()
                }
                .buttonStyle(.borderedProminent)
                
                if let msg = targetSavedMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
            }
        }
    }

    private var footerHelpSection: some View {
        HStack {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
            Text("未创建凭证？可前往 Google Cloud Console 免费创建桌面 OAuth 凭据。")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button("查看指引") {
                if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
    }

    private func loadExistingCredentials() {
        clientIdInput = authManager.getClientId() ?? ""
        clientSecretInput = authManager.getClientSecret() ?? ""
        targetFolderInput = authManager.getTargetFolder()
        createDateSubfolderInput = authManager.getCreateDateSubfolder()
        minVideoSizeMBInput = authManager.getMinVideoSizeMB()
    }

    private func saveCredentials() {
        authManager.saveClientCredentials(clientId: clientIdInput, clientSecret: clientSecretInput)
        saveSuccessMessage = "✅ 凭证已安全固化保存（0600 本地保护）！"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            saveSuccessMessage = nil
        }
    }
    
    private func saveTargetSettings() {
        authManager.setTargetFolder(targetFolderInput)
        authManager.setCreateDateSubfolder(createDateSubfolderInput)
        authManager.setMinVideoSizeMB(minVideoSizeMBInput)
        targetSavedMessage = "✅ 目标目录与过滤规则已成功保存！"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            targetSavedMessage = nil
        }
    }

    private func triggerOAuth() {
        isAuthenticating = true
        errorMessage = nil
        Task {
            do {
                try await authManager.startAuthorization()
                await MainActor.run {
                    self.isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAuthenticating = false
                }
            }
        }
    }
}
