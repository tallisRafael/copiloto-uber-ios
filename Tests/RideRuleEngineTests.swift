import XCTest
@testable import UberDriverHelper

/// Suíte de Testes Unitários (XCTest) para validar o Parser Regex, as Regras de Decisão,
/// a integração com o Apple Maps (MapKit) e o Motor de Aprendizado de Máquina (IA Local).
final class RideRuleEngineTests: XCTestCase {
    
    private var engine: RideRuleEngine!
    private var defaultSettings: RideSettings!
    
    override func setUp() {
        super.setUp()
        engine = RideRuleEngine()
        defaultSettings = RideSettings()
    }
    
    // MARK: - 1. Testes de Extração Regex (Parser OCR)
    
    func testParseStandardRideOCR() {
        let ocr = """
        R$ 12,91
        Est. de R$3,49/km
        4,97 (254) Verificado
        2 min (0.4 km) Av. Maringá, Jardim Verão
        9 minutos (3.3 km) Avenida João de Barro
        """
        
        guard let data = engine.parseOCRText(ocr) else {
            XCTFail("Falha ao extrair dados do OCR padrão.")
            return
        }
        
        XCTAssertEqual(data.valorTotal, 12.91, accuracy: 0.01)
        XCTAssertEqual(data.tempoTotal, 11.0, accuracy: 0.01)
        XCTAssertEqual(data.kmTotal, 3.7, accuracy: 0.01)
        XCTAssertEqual(data.notaPassageiro ?? 0.0, 4.97, accuracy: 0.01)
        XCTAssertTrue(data.passageiroVerificado)
    }
    
    // MARK: - 2. Testes do Apple Maps (MapKit Traffic Verification)
    
    func testAppleMapsCorrectsUberOverestimatedTime() {
        // Na Uber: 2 km levando 20 min (R$ 10,00 -> daria R$ 30/h e reprovaria no trânsito)
        // No Apple Maps: trânsito livre, leva apenas 6 min reais (R$ 100/h!)
        let ocr = """
        R$ 10,00
        4,96 (210) Verificado
        2 min (1.0 km) Av. Brasil, Centro
        18 minutos (1.0 km) Av. São Paulo, Zona 1
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let mapVerification = MapTrafficVerification(
            appleMapsTotalMinutes: 6.0,
            appleMapsTotalKm: 2.0,
            minutesDifferenceFromUber: -14.0
        )
        
        let verdict = engine.evaluate(
            ride: data,
            isTrafficModeEnabled: false,
            settings: defaultSettings,
            mapVerification: mapVerification
        )
        
        XCTAssertEqual(verdict.status, .approved)
        XCTAssertTrue(verdict.message.contains("MAPS TOP"))
    }
    
    func testAppleMapsDetectsHiddenTrafficTrap() {
        // Na Uber: 10 min (R$ 11,00 -> pareceria R$ 66/h)
        // No Apple Maps: engarrafamento real de 22 min (cai para R$ 30/h < R$ 35/h!)
        let ocr = """
        R$ 11,00
        4,95 (180) Verificado
        2 min (0.8 km) Av. Colombo
        8 minutos (3.2 km) Av. Morangueira
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let mapVerification = MapTrafficVerification(
            appleMapsTotalMinutes: 22.0,
            appleMapsTotalKm: 4.0,
            minutesDifferenceFromUber: 12.0
        )
        
        let verdict = engine.evaluate(
            ride: data,
            isTrafficModeEnabled: false,
            settings: defaultSettings,
            mapVerification: mapVerification
        )
        
        XCTAssertEqual(verdict.status, .rejected)
        XCTAssertTrue(verdict.message.contains("MAPS TRÂNSITO"))
    }
    
    // MARK: - 3. Testes do Aprendizado de Máquina (AdaptiveLearningEngine)
    
    func testLearnedDangerZoneRejected() {
        let ocr = """
        R$ 18,00
        4,95 (120) Verificado
        2 min (0.5 km) Av. Brasil
        10 minutos (5.0 km) Rua A, Jardim Olímpico
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let insight = LearnedRideInsight(
            regionName: "Jardim Olímpico",
            isLearnedDanger: true,
            isLearnedDeadhead: false,
            averageWaitMinutes: 0
        )
        
        let verdict = engine.evaluate(
            ride: data,
            isTrafficModeEnabled: false,
            settings: defaultSettings,
            learnedInsight: insight
        )
        
        XCTAssertEqual(verdict.status, .rejected)
        XCTAssertTrue(verdict.message.contains("VOCÊ EVITA"))
    }
    
    func testLearnedDeadheadZoneRejectedWhenLowKmPay() {
        let ocr = """
        R$ 14,00
        4,93 (90) Verificado
        3 min (1.0 km) Centro
        12 minutos (8.0 km) Rodovia, Parque Industrial
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let insight = LearnedRideInsight(
            regionName: "Parque Industrial",
            isLearnedDanger: false,
            isLearnedDeadhead: true,
            averageWaitMinutes: 22.0
        )
        
        let verdict = engine.evaluate(
            ride: data,
            isTrafficModeEnabled: false,
            settings: defaultSettings,
            learnedInsight: insight
        )
        
        XCTAssertEqual(verdict.status, .rejected)
        XCTAssertTrue(verdict.message.contains("VOLTA VAZIA"))
    }
    
    // MARK: - 4. Testes da Calibragem Maringá • Sarandi • Marialva
    
    func testMaringaToSarandiDoesNotChargeDeadheadReturn() {
        let ocr = """
        R$ 20,35
        4,94 (190) Verificado
        2 min (0.8 km) Av. Colombo, Zona 7
        16 minutos (10.2 km) Av. Londrina, Sarandi
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let verdict = engine.evaluate(ride: data, isTrafficModeEnabled: false, settings: defaultSettings)
        
        XCTAssertEqual(verdict.status, .approved)
    }
    
    func testSarandiToMaringaDetectedAsPaidReturnToBase() {
        let ocr = """
        R$ 16,50
        4,92 (140) Verificado
        2 min (0.7 km) Av. Maringá, Sarandi
        16 minutos (10.3 km) Av. Brasil, Zona 1, Maringá
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let verdict = engine.evaluate(ride: data, isTrafficModeEnabled: false, settings: defaultSettings)
        
        XCTAssertEqual(verdict.status, .goingHome)
        XCTAssertTrue(verdict.message.contains("VOLTA P/ MARINGÁ"))
    }
    
    func testMaringaToMarialvaStandardRideRejectedByDeadheadMath() {
        let ocr = """
        R$ 26,00
        4,95 (310) Verificado
        3 min (1.0 km) Av. Brasil, Centro
        21 minutos (17.0 km) Centro, Marialva
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let verdict = engine.evaluate(ride: data, isTrafficModeEnabled: false, settings: defaultSettings)
        
        XCTAssertEqual(verdict.status, .rejected)
        XCTAssertTrue(verdict.message.contains("VOLTA VAZIA (MARIALVA)"))
    }
    
    func testMaringaToMarialvaHighValueRideApprovedEvenWithDeadheadMath() {
        let ocr = """
        R$ 42,00
        4,98 (420) Verificado
        3 min (1.0 km) Av. Brasil, Centro
        21 minutos (17.0 km) Centro, Marialva
        """
        let data = try! XCTUnwrap(engine.parseOCRText(ocr))
        let verdict = engine.evaluate(ride: data, isTrafficModeEnabled: false, settings: defaultSettings)
        
        XCTAssertEqual(verdict.status, .approved)
        XCTAssertTrue(verdict.message.contains("MARIALVA TOP"))
    }
}
