# Authentication Roadmap

Keep onboarding as a local mock while the core invoice workflow is still being shaped. Add real authentication after invoices, business profile, clients, numbering, PDF output, and payment settings are stable enough to define account ownership.

## Current State

- Onboarding UI offers Apple, Google, and Email options.
- Each option currently completes onboarding locally.
- Completion is stored with `@AppStorage("hasCompletedOnboarding")`.
- No real user account, backend session, identity provider, or synced profile exists yet.

## Why Auth Is Deferred

Real authentication affects product architecture, not just the sign-in screen:

- account ownership for invoices, clients, items, and business profiles
- backend session handling
- cloud sync and multi-device behavior
- subscription ownership
- team access and roles
- account deletion and export obligations
- privacy policy and terms enforcement

Adding it too early would make the local invoice model harder to change.

## Later Auth Requirements

### Sign in with Apple

- Add Sign in with Apple capability.
- Configure Apple Developer identifiers.
- Request name/email only when needed.
- Handle private relay email addresses.
- Support account deletion.

### Google Sign-In

- Create Google OAuth client IDs.
- Add URL scheme configuration.
- Decide whether Google auth goes directly to the app or through the backend.
- Handle revoked tokens and failed refresh.

### Email Sign-In

Choose one:

- magic link email sign-in
- email/password with password reset
- one-time code sign-in

Required behavior:

- email verification
- rate limiting
- resend handling
- account recovery

### Backend Session Model

- Create user records.
- Issue app sessions or tokens.
- Store provider-linked identities.
- Support logout from one device and all devices.
- Support account deletion and data export.

### App Architecture

Add an auth abstraction before real provider work:

```swift
protocol AuthService {
    var currentUser: AuthUser? { get }
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func signInWithEmail(_ email: String) async throws
    func signOut() async throws
}
```

Initial implementation can stay local/mock. Real provider implementations can replace it later without rewriting onboarding.

## Suggested Trigger Point

Start real authentication when these are working locally:

- business profile setup
- client management
- invoice creation
- invoice numbering
- PDF preview/export
- invoice persistence
- basic settings

At that point, account ownership and sync boundaries will be clearer.
