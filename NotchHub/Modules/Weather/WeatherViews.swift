import SwiftUI

struct WeatherExpandedView: View {
    let module: WeatherModule

    var body: some View {
        if let snapshot = module.snapshot {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(snapshot.placeName, systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Image(systemName: WeatherCode.symbol(snapshot.weatherCode, isDay: snapshot.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 38))
                        Text(module.formatted(snapshot.temperature))
                            .font(.system(size: 44, weight: .light))
                    }
                    Text(WeatherCode.description(snapshot.weatherCode)).font(.headline)
                    Text("H \(module.formatted(snapshot.high))  L \(module.formatted(snapshot.low))")
                        .foregroundStyle(.secondary)
                    footer(snapshot)
                }
                .frame(width: 190, alignment: .leading)

                HStack(spacing: 0) {
                    ForEach(snapshot.hourly) { hour in
                        VStack(spacing: 6) {
                            Text(hour.time, format: .dateTime.hour())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: WeatherCode.symbol(hour.weatherCode, isDay: hour.isDay))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 16))
                                .frame(height: 20)
                            Text(module.formatted(hour.temperature)).font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            }
        } else {
            WeatherPlaceholder(module: module)
        }
    }

    @ViewBuilder
    private func footer(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 6) {
            if module.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                IconButton(icon: "arrow.clockwise", size: 8, help: "Refresh") {
                    Task { await module.refresh(force: true) }
                }
            }
            Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let error = module.errorMessage {
            Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
        }
    }
}

/// Shown before the first successful fetch: loading, error, or permission prompt.
private struct WeatherPlaceholder: View {
    let module: WeatherModule
    private var location: LocationService { .shared }

    var body: some View {
        VStack(spacing: 8) {
            if module.isLoading {
                ProgressView()
                Text("Loading weather…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "cloud.sun").font(.system(size: 28)).foregroundStyle(.secondary)
                Text(module.errorMessage ?? "No weather data yet.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack {
                    if location.isDenied {
                        Button("Open Location Settings") { location.openSystemSettings() }
                            .buttonStyle(PillButtonStyle())
                    }
                    Button("Set City…") { SettingsOpener.open(page: .module("weather")) }.buttonStyle(PillButtonStyle())
                    Button("Retry") { Task { await module.refresh(force: true) } }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WeatherCompactView: View {
    let module: WeatherModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ModuleTileHeader(icon: "location.fill", title: module.snapshot?.placeName ?? "Weather")
            if let snapshot = module.snapshot {
                HStack(spacing: 6) {
                    Image(systemName: WeatherCode.symbol(snapshot.weatherCode, isDay: snapshot.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 20))
                    Text(module.formatted(snapshot.temperature)).font(.system(size: 24, weight: .light))
                }
                Text(WeatherCode.description(snapshot.weatherCode)).font(.caption)
                Text("H \(module.formatted(snapshot.high)) L \(module.formatted(snapshot.low))")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if module.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(module.errorMessage ?? "No data").font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}

struct WeatherSettingsView: View {
    let module: WeatherModule
    @AppStorage(Prefs.weatherUnit) private var unit
    @AppStorage(Prefs.weatherUseManualLocation) private var useManual
    @AppStorage(Prefs.weatherCity) private var city
    @AppStorage(Prefs.weatherRefreshMinutes) private var refreshMinutes
    @State private var cityDraft = ""
    private var location: LocationService { .shared }

    var body: some View {
        Picker("Units", selection: $unit) {
            Text("°F").tag("fahrenheit")
            Text("°C").tag("celsius")
        }
        .pickerStyle(.segmented)
        Toggle("Use a manual location instead of my current location", isOn: $useManual)
        HStack {
            TextField("City", text: $cityDraft, prompt: Text("e.g. Chicago"))
                .onSubmit(applyCity)
            Button("Apply", action: applyCity)
        }
        Picker("Refresh every", selection: $refreshMinutes) {
            Text("15 minutes").tag(15)
            Text("30 minutes").tag(30)
            Text("1 hour").tag(60)
            Text("2 hours").tag(120)
        }
        HStack {
            switch location.authorization {
            case .denied, .restricted:
                Label("Location access denied", systemImage: "location.slash").foregroundStyle(.orange)
                Spacer()
                Button("Open System Settings") { location.openSystemSettings() }
            case .notDetermined:
                Label("Location permission not requested yet", systemImage: "location").foregroundStyle(.secondary)
                Spacer()
                Button("Allow Location") { location.requestAuthorization() }
            default:
                Label("Location access allowed", systemImage: "location.fill").foregroundStyle(.secondary)
            }
        }
        Button("Refresh Now") { Task { await module.refresh(force: true) } }
            .onAppear { cityDraft = city }
            .onChange(of: unit) { Task { await module.refresh() } }
            .onChange(of: useManual) { Task { await module.refresh() } }
        Text("Weather data by Open-Meteo.com").font(.caption).foregroundStyle(.secondary)
    }

    private func applyCity() {
        city = cityDraft.trimmingCharacters(in: .whitespaces)
        if !city.isEmpty { useManual = true }
        Task { await module.refresh(force: true) }
    }
}
