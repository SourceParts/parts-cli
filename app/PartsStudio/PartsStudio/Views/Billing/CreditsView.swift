import SwiftUI
import WebKit

struct CreditsView: View {
    @EnvironmentObject var appState: AppState
    @State private var balance: Int?
    @State private var tier: String = ""
    @State private var packages: [CreditPackage] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Balance card
                balanceCard

                // Quick actions
                quickActions

                // Credit packages
                if !packages.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Credit Packages")
                            .font(.headline)

                        ForEach(packages) { pkg in
                            CreditPackageCard(package: pkg) {
                                purchasePackage(pkg)
                            }
                        }
                    }
                }

                // Services pricing
                servicesPricing
            }
            .padding(24)
        }
        .onAppear { loadData() }
    }

    // MARK: - Balance Card

    @ViewBuilder
    private var balanceCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Credit Balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isLoading {
                        ProgressView()
                    } else if let bal = balance {
                        Text("\(bal.formatted()) credits")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                    } else {
                        Text("--")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(tier.isEmpty ? "Free" : tier.capitalized)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(tierColor)
                }
            }

            if let err = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { loadData() }
                        .font(.caption)
                        .buttonStyle(.link)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 12) {
            actionButton("Manage Subscription", icon: "creditcard", color: .blue) {
                openPortal()
            }
            actionButton("Transaction History", icon: "clock.arrow.circlepath", color: .purple) {
                openTransactions()
            }
            actionButton("API Keys", icon: "key", color: .orange) {
                openAPIKeys()
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Services Pricing

    @ViewBuilder
    private var servicesPricing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services")
                .font(.headline)

            let services: [(String, String, String, String)] = [
                ("Parts Search", "magnifyingglass", "1 credit/query", "Search millions of components"),
                ("BOM Analysis", "tablecells", "10 credits/file", "Upload and validate BOMs"),
                ("DFM Review", "cpu", "50 credits/board", "Design for manufacturability analysis"),
                ("Datasheet AI", "doc.text.magnifyingglass", "5 credits/query", "AI-powered datasheet Q&A"),
                ("IQC Inspection", "checkmark.shield", "25 credits/batch", "Incoming quality control"),
                ("X-Ray Inspection", "rays", "100 credits/board", "BGA and solder joint analysis"),
                ("Fab Quote", "hammer", "Free", "PCB fabrication quotes"),
                ("Component Sourcing", "cart", "5 credits/search", "Multi-distributor price comparison"),
            ]

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(services.enumerated()), id: \.offset) { _, svc in
                    HStack(spacing: 10) {
                        Image(systemName: svc.1)
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(svc.0)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(svc.2)
                                .font(.caption2)
                                .foregroundStyle(svc.2 == "Free" ? .green : .secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .help(svc.3)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = true
        error = nil

        Task {
            do {
                // Get balance via CLI
                let balanceOutput = try await CLIBridge.shared.run(["credits", "balance", "--json"])
                if let data = balanceOutput.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let bal = json["balance"] as? Int {
                    await MainActor.run { balance = bal }
                }
            } catch {
                // CLI might not have credits command yet — show placeholder
                await MainActor.run {
                    self.balance = nil
                    self.tier = "developer"
                    self.packages = CreditPackage.samples
                    self.error = "Connect your account to view live balance"
                }
            }

            await MainActor.run {
                if packages.isEmpty { packages = CreditPackage.samples }
                isLoading = false
            }
        }
    }

    private func purchasePackage(_ pkg: CreditPackage) {
        // Open Stripe Checkout in browser
        if let url = URL(string: "https://source.parts/pricing?package=\(pkg.sku)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openPortal() {
        if let url = URL(string: "https://source.parts/dashboard/billing") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openTransactions() {
        if let url = URL(string: "https://source.parts/dashboard/credits") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAPIKeys() {
        if let url = URL(string: "https://source.parts/dashboard/api-keys") {
            NSWorkspace.shared.open(url)
        }
    }

    private var tierColor: Color {
        switch tier {
        case "enterprise": return .purple
        case "professional": return .blue
        case "developer": return .green
        case "hobbyist": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Credit Package

struct CreditPackage: Identifiable {
    let id: String
    let sku: String
    let name: String
    let credits: Int
    let bonus: Int
    let priceCents: Int

    var priceFormatted: String {
        String(format: "$%.2f", Double(priceCents) / 100.0)
    }

    var totalCredits: Int { credits + bonus }

    var perCreditCents: Double {
        Double(priceCents) / Double(totalCredits)
    }

    static let samples: [CreditPackage] = [
        CreditPackage(id: "starter", sku: "credits-starter", name: "Starter", credits: 500, bonus: 0, priceCents: 999),
        CreditPackage(id: "builder", sku: "credits-builder", name: "Builder", credits: 2000, bonus: 200, priceCents: 2999),
        CreditPackage(id: "pro", sku: "credits-pro", name: "Professional", credits: 10000, bonus: 2000, priceCents: 9999),
        CreditPackage(id: "team", sku: "credits-team", name: "Team", credits: 50000, bonus: 15000, priceCents: 39999),
    ]
}

struct CreditPackageCard: View {
    let package: CreditPackage
    let onPurchase: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.body)
                    .fontWeight(.semibold)
                HStack(spacing: 4) {
                    Text("\(package.credits.formatted()) credits")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    if package.bonus > 0 {
                        Text("+\(package.bonus.formatted()) bonus")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }
                Text(String(format: "$%.3f/credit", package.perCreditCents / 100.0))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onPurchase) {
                Text(package.priceFormatted)
                    .font(.body)
                    .fontWeight(.bold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
