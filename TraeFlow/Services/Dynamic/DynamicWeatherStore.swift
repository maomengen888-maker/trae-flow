import Combine
import CoreLocation
import Foundation

struct DynamicDailyWeather: Identifiable, Equatable {
    let date: Date
    let conditionText: String
    let systemImage: String
    let maximumTemperature: Int
    let minimumTemperature: Int
    let rainProbability: Int

    var id: Date { date }
}

@MainActor
final class DynamicWeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = DynamicWeatherStore()

    @Published private(set) var cityName = "正在定位"
    @Published private(set) var temperatureText = "--°"
    @Published private(set) var conditionText = "天气加载中"
    @Published private(set) var rainProbability = 0
    @Published private(set) var systemImage = "cloud"
    @Published private(set) var forecastDays: [DynamicDailyWeather] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var manualCity = ""

    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private var hasRequestedLocationThisSession = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manualCity = defaults.string(forKey: "dynamicWeatherManualCity") ?? ""
    }

    func refresh() {
        if !manualCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchAndLoad(city: manualCity)
        } else {
            requestAutomaticLocation()
        }
    }

    func requestAutomaticLocation() {
        manualCity = ""
        defaults.removeObject(forKey: "dynamicWeatherManualCity")
        isLoading = true
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            guard !hasRequestedLocationThisSession else { return }
            hasRequestedLocationThisSession = true
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            cityName = "请设置城市"
            conditionText = "定位权限未开启"
            errorMessage = "可在设置中手动输入城市"
        @unknown default:
            isLoading = false
        }
    }

    func useManualCity(_ city: String) {
        let cleaned = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            requestAutomaticLocation()
            return
        }
        manualCity = cleaned
        defaults.set(cleaned, forKey: "dynamicWeatherManualCity")
        searchAndLoad(city: cleaned)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.isLoading = false
                self.cityName = "请设置城市"
                self.conditionText = "定位权限未开启"
                self.errorMessage = "可在设置中手动输入城市"
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.loadWeather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                fallbackCity: "当前位置"
            )
            self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            self.cityName = "天气不可用"
            self.conditionText = "定位失败"
            self.errorMessage = error.localizedDescription
        }
    }

    private func searchAndLoad(city: String) {
        isLoading = true
        errorMessage = nil
        guard var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else { return }
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
                guard let place = response.results?.first else {
                    throw WeatherError.cityNotFound
                }
                cityName = place.name
                loadWeather(latitude: place.latitude, longitude: place.longitude, fallbackCity: place.name)
            } catch {
                isLoading = false
                cityName = city
                conditionText = "无法获取天气"
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadWeather(latitude: Double, longitude: Double, fallbackCity: String) {
        isLoading = true
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
                let code = response.current.weatherCode
                temperatureText = "\(Int(response.current.temperature.rounded()))°"
                rainProbability = response.daily.precipitationProbability.first
                    ?? response.hourly.precipitationProbability.first
                    ?? 0
                let presentation = Self.presentation(for: code)
                conditionText = presentation.text
                systemImage = presentation.symbol
                forecastDays = Self.makeForecastDays(from: response.daily)
                if cityName == "正在定位" || cityName == "天气不可用" {
                    cityName = fallbackCity
                }
                isLoading = false
                errorMessage = nil
            } catch {
                isLoading = false
                cityName = fallbackCity
                conditionText = "无法获取天气"
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let name = placemarks?.first?.locality
                ?? placemarks?.first?.administrativeArea
                ?? "当前位置"
            Task { @MainActor in self?.cityName = name }
        }
    }

    private static func presentation(for code: Int) -> (text: String, symbol: String) {
        switch code {
        case 0: return ("晴", "sun.max.fill")
        case 1, 2: return ("多云", "cloud.sun.fill")
        case 3: return ("阴", "cloud.fill")
        case 45, 48: return ("有雾", "cloud.fog.fill")
        case 51...67, 80...82: return ("有雨", "cloud.rain.fill")
        case 71...77, 85, 86: return ("有雪", "cloud.snow.fill")
        case 95...99: return ("雷雨", "cloud.bolt.rain.fill")
        default: return ("天气变化", "cloud.fill")
        }
    }

    private static func makeForecastDays(from daily: ForecastResponse.Daily) -> [DynamicDailyWeather] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let count = [
            daily.time.count,
            daily.weatherCode.count,
            daily.maximumTemperature.count,
            daily.minimumTemperature.count,
            daily.precipitationProbability.count
        ].min() ?? 0

        return (0..<count).compactMap { index in
            guard let date = formatter.date(from: daily.time[index]) else { return nil }
            let presentation = presentation(for: daily.weatherCode[index])
            return DynamicDailyWeather(
                date: date,
                conditionText: presentation.text,
                systemImage: presentation.symbol,
                maximumTemperature: Int(daily.maximumTemperature[index].rounded()),
                minimumTemperature: Int(daily.minimumTemperature[index].rounded()),
                rainProbability: daily.precipitationProbability[index]
            )
        }
    }
}

private struct GeocodingResponse: Decodable {
    struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }
    let results: [Place]?
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct Hourly: Decodable {
        let precipitationProbability: [Int]

        enum CodingKeys: String, CodingKey {
            case precipitationProbability = "precipitation_probability"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let maximumTemperature: [Double]
        let minimumTemperature: [Double]
        let precipitationProbability: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case maximumTemperature = "temperature_2m_max"
            case minimumTemperature = "temperature_2m_min"
            case precipitationProbability = "precipitation_probability_max"
        }
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily
}

private enum WeatherError: LocalizedError {
    case cityNotFound

    var errorDescription: String? { "没有找到这个城市" }
}
