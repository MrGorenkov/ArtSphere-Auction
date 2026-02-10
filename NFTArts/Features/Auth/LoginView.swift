import SwiftUI

// MARK: - Auth Mode

private enum AuthMode: String, CaseIterable, Identifiable {
    case login
    case register

    var id: String { rawValue }
}

// MARK: - LoginView

/// Login / Register view for the NFT Arts app.
/// When `authManager.isAuthenticated` becomes `true` the parent `NFTArtsApp`
/// swaps to `MainTabView` automatically -- no navigation here is required.
struct LoginView: View {
    @StateObject private var authManager = AuthManager.shared
    @EnvironmentObject var lang: LanguageManager

    // MARK: Form state

    @State private var mode: AuthMode = .login

    // Login fields
    @State private var walletAddress: String = ""
    @State private var password: String = ""

    // Register-only fields
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var confirmPassword: String = ""

    // Local validation error (client-side)
    @State private var validationError: String?

    // MARK: Localization helpers

    private var isRu: Bool { lang.currentLanguage == .russian }

    // MARK: Body

    var body: some View {
        ZStack {
            backgroundGradient
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    headerSection
                    modePickerSection
                    formFields
                    errorSection
                    actionButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: mode) { _ in
            validationError = nil
            authManager.error = nil
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color.nftPurple.opacity(0.3),
                Color.nftBlue.opacity(0.2),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 56))
                .foregroundStyle(LinearGradient.nftPrimary)
                .shadow(color: .nftPurple.opacity(0.5), radius: 16, x: 0, y: 4)

            Text("NFT Arts")
                .font(NFTTypography.largeTitle)
                .foregroundStyle(LinearGradient.nftPrimary)

            Text(isRu
                 ? "Аукционы цифрового искусства"
                 : "Digital Art Auctions")
                .font(NFTTypography.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.bottom, 8)
    }

    // MARK: - Mode Picker

    private var modePickerSection: some View {
        Picker("", selection: $mode) {
            Text(isRu ? "Вход" : "Login")
                .tag(AuthMode.login)
            Text(isRu ? "Регистрация" : "Register")
                .tag(AuthMode.register)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
    }

    // MARK: - Form Fields

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: 16) {
            if mode == .register {
                AuthTextField(
                    icon: "person.fill",
                    placeholder: isRu ? "Имя пользователя" : "Username",
                    text: $username
                )

                AuthTextField(
                    icon: "person.text.rectangle",
                    placeholder: isRu ? "Отображаемое имя" : "Display Name",
                    text: $displayName
                )
            }

            AuthTextField(
                icon: "wallet.pass.fill",
                placeholder: isRu ? "Адрес кошелька" : "Wallet Address",
                text: $walletAddress,
                keyboardType: .asciiCapable,
                autocapitalization: .never
            )

            if mode == .register {
                AuthTextField(
                    icon: "envelope.fill",
                    placeholder: isRu ? "Email (необязательно)" : "Email (optional)",
                    text: $email,
                    keyboardType: .emailAddress,
                    autocapitalization: .never
                )
            }

            AuthSecureField(
                icon: "lock.fill",
                placeholder: isRu ? "Пароль" : "Password",
                text: $password
            )

            if mode == .register {
                AuthSecureField(
                    icon: "lock.rotation",
                    placeholder: isRu ? "Подтвердите пароль" : "Confirm Password",
                    text: $confirmPassword
                )
            }
        }
    }

    // MARK: - Error Display

    @ViewBuilder
    private var errorSection: some View {
        if let error = validationError ?? authManager.error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.nftOrange)
                Text(error)
                    .font(NFTTypography.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button(action: handleAction) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient.nftPrimary)
                    .frame(height: 56)
                    .shadow(color: .nftPurple.opacity(0.4), radius: 12, x: 0, y: 6)

                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(mode == .login
                         ? (isRu ? "Войти" : "Sign In")
                         : (isRu ? "Зарегистрироваться" : "Create Account"))
                        .font(NFTTypography.headline)
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(authManager.isLoading)
        .opacity(authManager.isLoading ? 0.7 : 1.0)
    }

    // MARK: - Actions

    private func handleAction() {
        validationError = nil
        authManager.error = nil

        switch mode {
        case .login:
            guard validateLogin() else { return }
            Task {
                await authManager.login(
                    walletAddress: walletAddress.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }

        case .register:
            guard validateRegister() else { return }
            Task {
                await authManager.register(
                    username: username.trimmingCharacters(in: .whitespaces),
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    walletAddress: walletAddress.trimmingCharacters(in: .whitespaces),
                    password: password,
                    email: email.isEmpty ? nil : email.trimmingCharacters(in: .whitespaces)
                )
            }
        }
    }

    // MARK: - Validation

    private func validateLogin() -> Bool {
        if walletAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            validationError = isRu
                ? "Введите адрес кошелька"
                : "Enter your wallet address"
            return false
        }
        if password.isEmpty {
            validationError = isRu
                ? "Введите пароль"
                : "Enter your password"
            return false
        }
        return true
    }

    private func validateRegister() -> Bool {
        if username.trimmingCharacters(in: .whitespaces).count < 3 {
            validationError = isRu
                ? "Имя пользователя должно содержать минимум 3 символа"
                : "Username must be at least 3 characters"
            return false
        }
        if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            validationError = isRu
                ? "Введите отображаемое имя"
                : "Enter a display name"
            return false
        }
        let trimmedWallet = walletAddress.trimmingCharacters(in: .whitespaces)
        if trimmedWallet.count < 3 {
            validationError = isRu
                ? "Адрес кошелька слишком короткий"
                : "Wallet address is too short"
            return false
        }
        if password.count < 6 {
            validationError = isRu
                ? "Пароль должен содержать минимум 6 символов"
                : "Password must be at least 6 characters"
            return false
        }
        if password != confirmPassword {
            validationError = isRu
                ? "Пароли не совпадают"
                : "Passwords do not match"
            return false
        }
        if !email.isEmpty {
            let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
            if email.range(of: emailRegex, options: .regularExpression) == nil {
                validationError = isRu
                    ? "Некорректный email"
                    : "Invalid email address"
                return false
            }
        }
        return true
    }
}

// MARK: - AuthTextField

/// Styled text field used on the auth screen.
private struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.nftPurple)
                .frame(width: 22)

            TextField("", text: $text, prompt: promptText)
                .font(NFTTypography.body)
                .foregroundColor(.white)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.nftPurple.opacity(0.3), lineWidth: 1)
        )
    }

    private var promptText: Text {
        Text(placeholder)
            .foregroundColor(.white.opacity(0.35))
    }
}

// MARK: - AuthSecureField

/// Styled secure text field with a visibility toggle used on the auth screen.
private struct AuthSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.nftPurple)
                .frame(width: 22)

            Group {
                if isRevealed {
                    TextField("", text: $text, prompt: promptText)
                } else {
                    SecureField("", text: $text, prompt: promptText)
                }
            }
            .font(NFTTypography.body)
            .foregroundColor(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.nftPurple.opacity(0.3), lineWidth: 1)
        )
    }

    private var promptText: Text {
        Text(placeholder)
            .foregroundColor(.white.opacity(0.35))
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environmentObject(LanguageManager.shared)
}
