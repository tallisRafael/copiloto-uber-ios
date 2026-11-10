import Foundation
import MapKit
import CoreLocation

/// Resultado da verificação de trânsito e tempo real no Apple Maps (MapKit)
struct MapTrafficVerification: Equatable {
    /// Tempo total estimado pelo Apple Maps em minutos (busca + viagem)
    let appleMapsTotalMinutes: Double
    /// Distância total estimada pelo Apple Maps em km
    let appleMapsTotalKm: Double
    /// Diferença em minutos entre o Apple Maps e o que o card da Uber mostrou (positivo = Maps diz que demora mais)
    let minutesDifferenceFromUber: Double
    
    /// Indica se o Apple Maps detectou trânsito muito pior do que a Uber informou (ex: +4 min)
    var hasHiddenTrafficTrap: Bool {
        minutesDifferenceFromUber >= 4.0
    }
    
    /// Indica se a Uber exagerou os minutos (ex: por causa de retorno de GPS), mas o Apple Maps mostra via rápida/livre
    var uberOverestimatedTime: Bool {
        minutesDifferenceFromUber <= -4.0
    }
}

/// Serviço nativo que consulta o Apple Maps (`MKLocalSearch` + `MKDirections`) em segundo plano
/// para validar se o tempo informado pela Uber condiz com o trânsito real da rua.
/// NÃO requer chave de API externa nem assinatura paga: utiliza o MapKit oficial embutido no iOS.
final class TrafficMapService: NSObject, CLLocationManagerDelegate {
    
    static let shared = TrafficMapService()
    
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentTask: Task<Void, Never>?
    
    /// Cache em memória para evitar repetir buscas de geocodificação de avenidas/bairros recorrentes de Maringá e Sarandi
    private let mapItemCache = NSCache<NSString, MKMapItem>()
    
    /// Coordenada central de Maringá - PR usada como âncora regional imediata caso o GPS ainda não tenha respondido
    private let maringaDefaultCoordinate = CLLocationCoordinate2D(latitude: -23.420999, longitude: -51.933056)
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        mapItemCache.countLimit = 120
    }
    
    /// Solicita permissão básica de localização para que o Apple Maps busque ruas sempre na cidade atual do motorista
    func requestLocationAnchorIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Caso o GPS não esteja disponível, o serviço utiliza o sufixo `cidadePadrao` configurado nas preferências
    }
    
    /// Cancela qualquer busca em andamento caso uma nova corrida toque
    func cancelPendingCheck() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    /// Consulta no Apple Maps o tempo real de deslocamento com trânsito (`transportType = .automobile`)
    /// entre o endereço de embarque e o endereço de destino extraídos pelo OCR.
    func verifyRouteTraffic(
        for ride: RideExtractedData,
        cityContext: String,
        completion: @escaping (MapTrafficVerification?) -> Void
    ) {
        cancelPendingCheck()
        requestLocationAnchorIfNeeded()
        
        let pickupQuery = enrichAddress(ride.enderecoBusca, withCity: cityContext)
        let dropoffQuery = enrichAddress(ride.enderecoDestino, withCity: cityContext)
        
        guard !pickupQuery.isEmpty, !dropoffQuery.isEmpty else {
            completion(nil)
            return
        }
        
        currentTask = Task {
            do {
                // Dispara a geocodificação de embarque e destino em PARALELO para cortar a latência pela metade (~0.35s)
                async let pickupTask = searchMapItem(query: pickupQuery)
                async let dropoffTask = searchMapItem(query: dropoffQuery)
                
                let (pickupItem, dropoffItem) = try await (pickupTask, dropoffTask)
                
                guard let validPickup = pickupItem,
                      let validDropoff = dropoffItem,
                      !Task.isCancelled else {
                    await MainActor.run { completion(nil) }
                    return
                }
                
                let request = MKDirections.Request()
                request.source = validPickup
                request.destination = validDropoff
                request.transportType = .automobile
                request.departureDate = Date() // Calcula com base no trânsito de AGORA
                
                let directions = MKDirections(request: request)
                let response = try await directions.calculate()
                
                guard !Task.isCancelled, let primaryRoute = response.routes.first else {
                    await MainActor.run { completion(nil) }
                    return
                }
                
                // Soma o tempo de busca com o tempo real da viagem calculado pelo Apple Maps
                let mapsTripMinutes = primaryRoute.expectedTravelTime / 60.0
                let mapsTripKm = primaryRoute.distance / 1000.0
                
                let totalMapsMinutes = max(1.0, ride.tempoBuscaMin + mapsTripMinutes)
                let totalMapsKm = ride.kmBusca + mapsTripKm
                let diffMinutes = totalMapsMinutes - ride.tempoTotal
                
                let verification = MapTrafficVerification(
                    appleMapsTotalMinutes: totalMapsMinutes,
                    appleMapsTotalKm: totalMapsKm,
                    minutesDifferenceFromUber: diffMinutes
                )
                
                await MainActor.run {
                    completion(verification)
                }
            } catch {
                await MainActor.run {
                    completion(nil)
                }
            }
        }
    }
    
    private func enrichAddress(_ address: String, withCity city: String) -> String {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else { return address }
        
        // Se o endereço já menciona Maringá, Sarandi, Marialva, Paiçandu, Iguatemi ou Floriano,
        // evita anexar "Maringá, PR" em cima de "Sarandi" ou "Marialva"!
        let regionalCities = ["Maringá", "Maringa", "Sarandi", "Marialva", "Paiçandu", "Paicandu", "Iguatemi", "Floriano"]
        let alreadyHasCity = regionalCities.contains { address.localizedCaseInsensitiveContains($0) }
            || address.localizedCaseInsensitiveContains(trimmedCity)
        
        if alreadyHasCity {
            return address.localizedCaseInsensitiveContains("PR") ? address : "\(address), PR"
        }
        return "\(address), \(trimmedCity)"
    }
    
    private func searchMapItem(query: String) async throws -> MKMapItem? {
        let cacheKey = query.lowercased() as NSString
        if let cachedItem = mapItemCache.object(forKey: cacheKey) {
            return cachedItem
        }
        
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = query
        
        // Usa a coordenada GPS atual do motorista ou o centro de Maringá como âncora num raio de 50 km
        let anchorCenter = currentLocation?.coordinate ?? maringaDefaultCoordinate
        searchRequest.region = MKCoordinateRegion(
            center: anchorCenter,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
        
        let search = MKLocalSearch(request: searchRequest)
        let response = try await search.start()
        if let firstItem = response.mapItems.first {
            mapItemCache.setObject(firstItem, forKey: cacheKey)
            return firstItem
        }
        return nil
    }
}
