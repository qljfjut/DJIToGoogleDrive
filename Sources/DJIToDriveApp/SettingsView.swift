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
    @ObservedObject var loc: LocalizationManager = .shared
    
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
                languageSection
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
        .frame(width: 500, height: 640)
        .onAppear {
            loadExistingCredentials()
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.accentColor)
                Text(loc.languageSetting)
                    .font(.headline)
                Spacer()
                Picker("", selection: $loc.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.title)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Drive \(loc.preferencesTitle)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(loc.credentialsSubheader)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.credentialsSection)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Client ID:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField("123456...apps.googleusercontent.com", text: $clientIdInput)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if let pasteString = NSPasteboard.general.string(forType: .string) {
                            clientIdInput = pasteString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label(loc.paste, systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Client ID")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Client Secret:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    if showSecret {
                        TextField("GOCSPX-...", text: $clientSecretInput)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("GOCSPX-...", text: $clientSecretInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showSecret.toggle()
                    } label: {
                        Image(systemName: showSecret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        if let pasteString = NSPasteboard.general.string(forType: .string) {
                            clientSecretInput = pasteString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label(loc.paste, systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            HStack {
                Button(loc.saveToKeychain) {
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
            Text(loc.authStatusSection)
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(authManager.isAuthenticated ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(authManager.isAuthenticated ? loc.connectedGoogleDrive : loc.notAuthorizedGoogleDrive)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let email = authManager.userEmail {
                        Text(loc.currentAccountLabel(email))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if authManager.isAuthenticated {
                    Button(loc.signOut) {
                        authManager.signOut()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(isAuthenticating ? loc.openingBrowser : loc.signInGoogle) {
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
            Text(loc.targetFolderSection)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.targetFolderLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField(loc.targetFolderPlaceholder, text: $targetFolderInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        if let pasteString = NSPasteboard.general.string(forType: .string) {
                            targetFolderInput = pasteString.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label(loc.paste, systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Toggle(loc.createDateSubfolder, isOn: $createDateSubfolderInput)
                .font(.subheadline)
            
            HStack {
                Text(loc.junkFilterThresholdLabel)
                    .font(.subheadline)
                Stepper("\(minVideoSizeMBInput) MB", value: $minVideoSizeMBInput, in: 1...100)
                    .frame(width: 140)
                Text(loc.junkFilterExplanation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button(loc.saveTargetSettingsBtn) {
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
            Text(loc.helpGuide)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button(loc.viewGuide) {
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
        saveSuccessMessage = loc.credentialsSavedSuccess
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            saveSuccessMessage = nil
        }
    }
    
    private func saveTargetSettings() {
        authManager.setTargetFolder(targetFolderInput)
        authManager.setCreateDateSubfolder(createDateSubfolderInput)
        authManager.setMinVideoSizeMB(minVideoSizeMBInput)
        targetSavedMessage = loc.targetSettingsSavedSuccess
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
