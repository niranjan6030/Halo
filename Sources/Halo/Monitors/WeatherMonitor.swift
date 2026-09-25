import AppKit
import CoreLocation
import HaloCore
import SwiftUI

/// Current conditions and a short forecast for where you are.
///
/// Apple's WeatherKit needs a paid developer account, so this uses Open-Meteo,
/// which is free and needs no key. Only a coarse latitude and longitude leave the
/// Mac, and only while the weather is switched on.
@MainActor
final class WeatherMonitor: NSObject, ObservableObject {
    struct Conditions: Equatable {
        var temperature: Double
        var feelsLike: Double
        var humidity: Int
        var windSpeed: Double
        var code: Int
        var high: Double
        var low: Double
        var place: String
        var hourly: [Hour]
        var days: [Day]
        /// When rain (or snow) is expected to start within the next two hours, if it isn't already.
        var rainStart: Date?
        var updated: Date
    }

    struct Hour: Equatable, Identifiable {
        var id: Date { time }
        var time: Date
        var temperature: Double
        var code: Int
    }

    struct Day: Equatable, Identifiable {
        var id: Date { date }
        var date: Date
        var high: Double
        var low: Double
        var code: Int
    }

    @Published private(set) var conditions: Conditions?
    @Published private(set) var failure: String?
    /// Celsius unless the user's region uses Fahrenheit.
    /// Set from the user's choice; falls back to whatever the Mac's region implies.
    var unit: TemperatureUnit = .automatic
    var usesFahrenheit: Bool {
        unit.prefersFahrenheit ?? (Locale.current.measurementSystem != .metric)
    }

    private let locations = CLLocationManager()
    private var timer: Timer?
    private var isRunning = false
    private var lastCoordinate: CLLocationCoordinate2D?
    private var isFetching = false
    /// A city typed in Settings; empty means work it out from this Mac.
    private var city = ""
    private var placeOverride: String?
    private var fallbackWork: DispatchWorkItem?

    override init() {
        super.init()
        locations.delegate = self
        locations.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Called by the controller when the city in Settings changes.
    /// Switching units means the numbers already on screen are in the wrong one, so
    /// the readings are thrown away and fetched again.
    func updateUnit(_ unit: TemperatureUnit) {
        guard unit != self.unit else { return }
        self.unit = unit
        conditions = nil
        failure = nil
        guard isRunning else { return }
        refresh()
    }

    func updateCity(_ city: String) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != self.city else { return }
        self.city = trimmed
        lastCoordinate = nil
        placeOverride = nil
        conditions = nil
        failure = nil
        guard isRunning else { return }
        resolve()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        resolve()
        // Conditions move slowly; a refresh every quarter of an hour is plenty.
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.resolve() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        conditions = nil
        failure = nil
    }

    func refresh() {
        failure = nil
        resolve()
    }

    /// Works out where to report the weather for: the city from Settings, this Mac's
    /// location, or — when macOS won't hand that out — the city of its time zone.
    private func resolve() {
        guard isRunning else { return }
        if let lastCoordinate {
            fetch(for: lastCoordinate)
            return
        }
        if !city.isEmpty {
            geocode(city)
            return
        }

        switch locations.authorizationStatus {
        case .notDetermined:
            locations.requestWhenInUseAuthorization()
            locations.requestLocation()
        case .denied, .restricted:
            useTimeZoneCity()
            return
        default:
            locations.requestLocation()
        }

        // A locally-signed app often never gets a location prompt, and the request
        // simply fails, so fall back if nothing has arrived shortly.
        fallbackWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.lastCoordinate == nil else { return }
            self.useTimeZoneCity()
        }
        fallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func useTimeZoneCity() {
        // "Asia/Kolkata" -> "Kolkata": the right region, if not the exact town.
        let identifier = TimeZone.current.identifier
        let name = identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
        guard let name, !name.isEmpty else {
            failure = "Set your city in Settings"
            return
        }
        geocode(name, isApproximate: true)
    }

    private func geocode(_ query: String, isApproximate: Bool = false) {
        CLGeocoder().geocodeAddressString(query) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                guard let placemark = placemarks?.first, let location = placemark.location else {
                    self.failure = isApproximate ? "Set your city in Settings" : "Couldn't find “\(query)”"
                    return
                }
                self.placeOverride = placemark.locality ?? query
                self.lastCoordinate = location.coordinate
                self.failure = nil
                self.fetch(for: location.coordinate)
            }
        }
    }

    private func fetch(for coordinate: CLLocationCoordinate2D) {
        guard isRunning, !isFetching else { return }
        isFetching = true

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "minutely_15", value: "precipitation"),
            URLQueryItem(name: "forecast_minutely_15", value: "12"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "4"),
        ]
        if usesFahrenheit {
            components.queryItems? += [
                URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
                URLQueryItem(name: "wind_speed_unit", value: "mph"),
            ]
        }
        guard let url = components.url else {
            isFetching = false
            return
        }

        Task { [weak self] in
            defer { Task { @MainActor in self?.isFetching = false } }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: request)
                let override = await MainActor.run { self?.placeOverride }
                let place: String
                if let override {
                    place = override
                } else {
                    place = await Self.placeName(for: coordinate)
                }
                guard let parsed = Self.parse(data, place: place) else { return }
                await MainActor.run {
                    guard let self, self.isRunning else { return }
                    self.conditions = parsed
                    self.failure = nil
                }
            } catch {
                await MainActor.run {
                    guard let self, self.isRunning else { return }
                    // Keep showing the last reading; just note it couldn't refresh.
                    if self.conditions == nil { self.failure = "Weather unavailable" }
                }
            }
        }
    }

    private nonisolated static func placeName(for coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let placemark = placemarks?.first
        return placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea ?? "Your location"
    }

    private nonisolated static func parse(_ data: Data, place: String) -> Conditions? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temperature = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int,
              let daily = json["daily"] as? [String: Any],
              let dailyTimes = daily["time"] as? [String],
              let highs = daily["temperature_2m_max"] as? [Double],
              let lows = daily["temperature_2m_min"] as? [Double],
              let dailyCodes = daily["weather_code"] as? [Int] else { return nil }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var hours: [Hour] = []
        if let hourly = json["hourly"] as? [String: Any],
           let times = hourly["time"] as? [String],
           let temperatures = hourly["temperature_2m"] as? [Double],
           let codes = hourly["weather_code"] as? [Int] {
            let now = Date()
            for (index, time) in times.enumerated() where index < temperatures.count && index < codes.count {
                guard let date = hourFormatter.date(from: time), date > now.addingTimeInterval(-1800) else { continue }
                hours.append(Hour(time: date, temperature: temperatures[index], code: codes[index]))
                if hours.count == 8 { break }
            }
        }

        // Rain on the way: dry now, then at least 0.1 mm in a 15-minute slot within two hours.
        var rainStart: Date?
        if let minutely = json["minutely_15"] as? [String: Any],
           let times = minutely["time"] as? [String],
           let amounts = minutely["precipitation"] as? [Double] {
            let now = Date()
            var dryNow = true
            for (index, time) in times.enumerated() where index < amounts.count {
                guard let date = hourFormatter.date(from: time) else { continue }
                if date.addingTimeInterval(900) <= now { continue }
                if date <= now {
                    dryNow = amounts[index] < 0.1
                    continue
                }
                guard dryNow, date.timeIntervalSince(now) <= 7200 else { break }
                if amounts[index] >= 0.1 {
                    rainStart = date
                    break
                }
            }
        }

        var days: [Day] = []
        for (index, time) in dailyTimes.enumerated() where index < highs.count && index < lows.count && index < dailyCodes.count {
            guard let date = dayFormatter.date(from: time) else { continue }
            days.append(Day(date: date, high: highs[index], low: lows[index], code: dailyCodes[index]))
        }

        return Conditions(
            temperature: temperature,
            feelsLike: current["apparent_temperature"] as? Double ?? temperature,
            humidity: current["relative_humidity_2m"] as? Int ?? 0,
            windSpeed: current["wind_speed_10m"] as? Double ?? 0,
            code: code,
            high: highs.first ?? temperature,
            low: lows.first ?? temperature,
            place: place,
            hourly: hours,
            days: days,
            rainStart: rainStart,
            updated: Date()
        )
    }
}

extension WeatherMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.fallbackWork?.cancel()
            self.lastCoordinate = coordinate
            self.placeOverride = nil
            self.failure = nil
            self.fetch(for: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.isRunning, self.lastCoordinate == nil, self.city.isEmpty else { return }
            self.useTimeZoneCity()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.isRunning else { return }
            switch manager.authorizationStatus {
            case .denied, .restricted: self.useTimeZoneCity()
            case .notDetermined: break
            default:
                self.failure = nil
                manager.requestLocation()
            }
        }
    }
}

/// WMO weather codes, as an icon and a few words.
enum WeatherLook {
    static func symbol(_ code: Int, night: Bool = false) -> String {
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Thunderstorms with hail"
        default: return "—"
        }
    }

    /// The colour of the sky for a tile background: blue by day, deep indigo by night,
    /// slate when it's grey, darker still for storms.
    static func sky(_ code: Int, night: Bool) -> Color {
        switch code {
        case 0, 1, 2: return night ? Color(red: 0.16, green: 0.2, blue: 0.45) : Color(red: 0.2, green: 0.5, blue: 0.95)
        case 3, 45, 48: return night ? Color(red: 0.22, green: 0.25, blue: 0.33) : Color(red: 0.42, green: 0.5, blue: 0.62)
        case 95, 96, 99: return Color(red: 0.27, green: 0.23, blue: 0.42)
        default: return night ? Color(red: 0.18, green: 0.24, blue: 0.38) : Color(red: 0.3, green: 0.42, blue: 0.6)
        }
    }

    static func tint(_ code: Int) -> Color {
        switch code {
        case 0, 1: return .yellow
        case 2, 3, 45, 48: return .gray
        case 71, 73, 75, 77, 85, 86: return .cyan
        case 95, 96, 99: return .purple
        default: return .blue
        }
    }
}
