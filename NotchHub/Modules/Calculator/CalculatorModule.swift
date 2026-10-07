import AppKit
import SwiftUI

extension Prefs {
    static let converterCategory = PrefKey("calculator.converterCategory", "length")
    static let currencyEnabled = PrefKey("calculator.currency", true)
}

/// Unit categories backed by Foundation's Measurement types (plus currency).
enum ConverterCategory: String, CaseIterable, Identifiable {
    case length, weight, temperature, volume, time, currency
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// (symbol shown, Foundation unit). Currency uses `CurrencyRates` instead.
    var units: [(String, Dimension)] {
        switch self {
        case .length: [("mm", UnitLength.millimeters), ("cm", UnitLength.centimeters), ("m", UnitLength.meters),
                       ("km", UnitLength.kilometers), ("in", UnitLength.inches), ("ft", UnitLength.feet),
                       ("yd", UnitLength.yards), ("mi", UnitLength.miles)]
        case .weight: [("mg", UnitMass.milligrams), ("g", UnitMass.grams), ("kg", UnitMass.kilograms),
                       ("oz", UnitMass.ounces), ("lb", UnitMass.pounds), ("st", UnitMass.stones), ("t", UnitMass.metricTons)]
        case .temperature: [("°C", UnitTemperature.celsius), ("°F", UnitTemperature.fahrenheit), ("K", UnitTemperature.kelvin)]
        case .volume: [("ml", UnitVolume.milliliters), ("l", UnitVolume.liters), ("tsp", UnitVolume.teaspoons),
                       ("tbsp", UnitVolume.tablespoons), ("fl oz", UnitVolume.fluidOunces), ("cup", UnitVolume.cups),
                       ("pt", UnitVolume.pints), ("qt", UnitVolume.quarts), ("gal", UnitVolume.gallons)]
        case .time: [("ms", UnitDuration.milliseconds), ("s", UnitDuration.seconds), ("min", UnitDuration.minutes),
                     ("h", UnitDuration.hours)]
        case .currency: []
        }
    }
}

/// Daily exchange rates from frankfurter.app (free, no API key; ECB data).
@Observable
@MainActor
final class CurrencyRates {
    static let shared = CurrencyRates()

    private struct Cache: Codable {
        var base: String
        var date: String
        var rates: [String: Double]
        var fetchedAt: Date
    }

    private(set) var rates: [String: Double] = [:]
    private(set) var asOf: String?
    private(set) var error: String?
    private(set) var isLoading = false

    private static let cacheFile = "currency-rates.json"
    static let base = "EUR"

    private init() {
        if let cache = JSONStore.load(Cache.self, from: Self.cacheFile) {
            rates = cache.rates
            asOf = cache.date
        }
    }

    var currencies: [String] { ([Self.base] + rates.keys).sorted() }

    /// Fetches at most once a day.
    func refreshIfNeeded() async {
        let cache = JSONStore.load(Cache.self, from: Self.cacheFile)
        if let cache, Date.now.timeIntervalSince(cache.fetchedAt) < 86_400, !cache.rates.isEmpty { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let url = URL(string: "https://api.frankfurter.app/latest?from=\(Self.base)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Response: Decodable { let base: String; let date: String; let rates: [String: Double] }
            let response = try JSONDecoder().decode(Response.self, from: data)
            rates = response.rates
            asOf = response.date
            error = nil
            JSONStore.save(Cache(base: response.base, date: response.date, rates: response.rates, fetchedAt: .now),
                           to: Self.cacheFile)
        } catch {
            self.error = rates.isEmpty ? "Couldn't load exchange rates." : nil
        }
    }

    func convert(_ value: Double, from: String, to: String) -> Double? {
        func perEuro(_ code: String) -> Double? { code == Self.base ? 1 : rates[code] }
        guard let f = perEuro(from), let t = perEuro(to), f > 0 else { return nil }
        return value / f * t
    }
}

/// Typed calculator with history, plus a unit/currency converter.
@Observable
@MainActor
final class CalculatorModule: NotchModule {
    let id = "calculator"
    let name = "Calculator"
    let icon = "plusminus.circle.fill"

    var expression = ""
    private(set) var history: [(expression: String, result: String)] = []

    /// Live result of the current expression, or an error message.
    var result: Result<Double, ExpressionEvaluator.EvalError> {
        do { return .success(try ExpressionEvaluator.evaluate(expression)) }
        catch let error as ExpressionEvaluator.EvalError { return .failure(error) }
        catch { return .failure(.empty) }
    }

    static func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "Not a number" : (value > 0 ? "∞" : "−∞") }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumSignificantDigits = 12
        formatter.usesSignificantDigits = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Commits the current expression to history (Return key).
    func commit() {
        guard case .success(let value) = result else { return }
        history.insert((expression, Self.format(value)), at: 0)
        if history.count > 8 { history.removeLast() }
        expression = Self.format(value)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func compactView() -> AnyView { AnyView(CalculatorCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(CalculatorExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(CalculatorSettingsView()) }
}

struct CalculatorExpandedView: View {
    @Bindable var module: CalculatorModule

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            calculator.frame(maxWidth: .infinity)
            Divider().overlay(Color.white.opacity(0.1))
            UnitConverterView().frame(maxWidth: .infinity)
        }
    }

    private var calculator: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "plusminus", title: "Calculator")
            TextField("e.g. (12 + 8) × 1.5", text: $module.expression)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
                .onSubmit { module.commit() }
                .accessibilityLabel("Expression")
            HStack {
                switch module.result {
                case .success(let value):
                    let text = CalculatorModule.format(value)
                    Text("= \(text)")
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textSelection(.enabled)
                    Spacer()
                    IconButton(icon: "doc.on.doc", size: 10, help: "Copy result") { module.copy(text) }
                case .failure(let error):
                    Text(module.expression.isEmpty ? "Type a calculation" : (error.errorDescription ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(module.history.enumerated()), id: \.offset) { _, item in
                        Button {
                            module.expression = item.expression
                        } label: {
                            HStack {
                                Text(item.expression).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(item.result).monospacedDigit()
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct UnitConverterView: View {
    @AppStorage(Prefs.converterCategory) private var categoryRaw
    @AppStorage(Prefs.currencyEnabled) private var currencyEnabled
    @State private var input = "1"
    @State private var fromIndex = 0
    @State private var toIndex = 1
    @State private var fromCurrency = "USD"
    @State private var toCurrency = "EUR"
    private var rates: CurrencyRates { .shared }

    private var categories: [ConverterCategory] {
        ConverterCategory.allCases.filter { $0 != .currency || currencyEnabled }
    }

    private var category: ConverterCategory {
        let c = ConverterCategory(rawValue: categoryRaw) ?? .length
        return categories.contains(c) ? c : .length
    }

    private var value: Double? {
        (try? ExpressionEvaluator.evaluate(input)) ?? Double(input)
    }

    private var output: String {
        guard let value else { return "—" }
        if category == .currency {
            guard let converted = rates.convert(value, from: fromCurrency, to: toCurrency) else { return "—" }
            return converted.formatted(.number.precision(.fractionLength(2)))
        }
        let units = category.units
        guard units.indices.contains(fromIndex), units.indices.contains(toIndex) else { return "—" }
        let converted = Measurement(value: value, unit: units[fromIndex].1).converted(to: units[toIndex].1).value
        return CalculatorModule.format((converted * 1e9).rounded() / 1e9)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Convert", selection: Binding(get: { category }, set: { newValue in
                categoryRaw = newValue.rawValue
                fromIndex = 0
                toIndex = min(1, newValue.units.count - 1)
            })) {
                ForEach(categories) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            HStack(spacing: 6) {
                TextField("Value", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .accessibilityLabel("Value to convert")
                unitPicker(from: true)
            }
            HStack(spacing: 6) {
                Text(output)
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 90, alignment: .leading)
                    .textSelection(.enabled)
                unitPicker(from: false)
                IconButton(icon: "arrow.up.arrow.down", size: 9, help: "Swap units") { swap() }
            }
            if category == .currency {
                Group {
                    if let error = rates.error {
                        Text(error).foregroundStyle(.orange)
                    } else if let date = rates.asOf {
                        Text("ECB rates from \(date) via frankfurter.app")
                    } else if rates.isLoading {
                        Text("Loading rates…")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .task { await rates.refreshIfNeeded() }
            }
        }
    }

    @ViewBuilder
    private func unitPicker(from: Bool) -> some View {
        if category == .currency {
            Picker(from ? "From" : "To", selection: from ? $fromCurrency : $toCurrency) {
                ForEach(rates.currencies, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        } else {
            Picker(from ? "From" : "To", selection: from ? $fromIndex : $toIndex) {
                ForEach(Array(category.units.enumerated()), id: \.offset) { index, unit in
                    Text(unit.0).tag(index)
                }
            }
            .labelsHidden()
        }
    }

    private func swap() {
        if category == .currency {
            (fromCurrency, toCurrency) = (toCurrency, fromCurrency)
        } else {
            (fromIndex, toIndex) = (toIndex, fromIndex)
        }
    }
}

struct CalculatorCompactView: View {
    @Bindable var module: CalculatorModule

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ModuleTileHeader(icon: "plusminus", title: "Calculator")
            TextField("2 + 2", text: $module.expression)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit { module.commit() }
            if case .success(let value) = module.result {
                HStack {
                    Text("= " + CalculatorModule.format(value)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    IconButton(icon: "doc.on.doc", size: 8, help: "Copy result", tooltipEdge: .top) {
                        module.copy(CalculatorModule.format(value))
                    }
                }
            }
        }
    }
}

struct CalculatorSettingsView: View {
    @AppStorage(Prefs.currencyEnabled) private var currencyEnabled

    var body: some View {
        Toggle("Currency conversion (downloads daily rates from frankfurter.app)", isOn: $currencyEnabled)
        Text("Calculator supports + − × ÷ ^ %, parentheses, pi, e, sqrt, sin, cos, tan, ln, log, abs, round, floor and ceil. Press Return to keep a result in the history.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
