import SwiftUI

/// The colors and symbols from calculum.dev: every category has one bright tone.
enum Theme {
  static let ink = Color(hex: 0x1F1A14)
  static let tomato = Color(hex: 0xFF6847)
  static let sun = Color(hex: 0xFFC83D)
  static let mint = Color(hex: 0x4FD1A1)
  static let sky = Color(hex: 0x5AA9FF)
  static let lilac = Color(hex: 0xB197FC)
  static let bubblegum = Color(hex: 0xFF8CC6)
  static let lime = Color(hex: 0xC2E85A)
  static let tangerine = Color(hex: 0xFFA04D)
  static let seriesColors = [Color.primary, Color(hex: 0x2B7DE9), Color(hex: 0xF0532F)]

  static func tone(_ category: String) -> Color {
    switch category {
    case "money", "banking-borrowing", "sustainability-waste": mint
    case "housing-moving", "time-lifestyle", "tech-digital": sky
    case "home-diy", "cooking-kitchen": tangerine
    case "bills-energy", "insurance-protection": sun
    case "travel", "shipping-logistics": bubblegum
    case "transport", "family-events", "fitness-activity": tomato
    case "shopping-food", "garden-outdoors": lime
    case "work-business", "taxes-payroll", "learning-career": lilac
    default: sun
    }
  }

  static func symbol(_ category: String) -> String {
    switch category {
    case "money": "banknote.fill"
    case "housing-moving": "house.fill"
    case "home-diy": "hammer.fill"
    case "bills-energy": "bolt.fill"
    case "travel": "airplane"
    case "transport": "car.fill"
    case "shopping-food": "cart.fill"
    case "work-business": "briefcase.fill"
    case "family-events": "gift.fill"
    case "time-lifestyle": "hourglass"
    case "banking-borrowing": "building.columns.fill"
    case "taxes-payroll": "percent"
    case "insurance-protection": "umbrella.fill"
    case "garden-outdoors": "leaf.fill"
    case "cooking-kitchen": "fork.knife"
    case "fitness-activity": "figure.run"
    case "tech-digital": "laptopcomputer"
    case "shipping-logistics": "shippingbox.fill"
    case "sustainability-waste": "arrow.3.trianglepath"
    case "learning-career": "graduationcap.fill"
    default: "equal"
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

/// A symbol on a small rounded tile in a bright tone, like the icons in System Settings.
struct ToneIcon: View {
  let symbol: String
  let tone: Color
  var size: CGFloat = 20

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.52, weight: .bold))
      .foregroundStyle(Theme.ink)
      .frame(width: size, height: size)
      .background(tone, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
  }
}

struct CategoryIcon: View {
  let category: String
  var size: CGFloat = 20

  var body: some View {
    ToneIcon(symbol: Theme.symbol(category), tone: Theme.tone(category), size: size)
  }
}

/// A rounded panel for each section of a calculator.
struct SectionCard<Content: View>: View {
  let title: String
  var subtitle: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(.title2, design: .rounded, weight: .bold))
        if let subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      content
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
  }
}