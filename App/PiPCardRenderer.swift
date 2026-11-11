import UIKit

/// Desenha o card flutuante no padrão GigU usando apenas UIKit/CoreGraphics.
/// Diferente do SwiftUI (`drawHierarchy`), este desenho funciona mesmo com o app em
/// SEGUNDO PLANO atrás da Uber — é isso que faz o PiP atualizar quando a corrida toca.
enum PiPCardRenderer {
    
    /// Proporção ~1,68:1 -> o iOS abre a janela PiP grande e alta (não aquela faixa fininha)
    static let canvasSize = CGSize(width: 420, height: 250)
    
    struct Input {
        let verdict: RideVerdict
        let metaAtual: Double
        let metaTotal: Double
        let minGanhoKm: Double
        let minGanhoHora: Double
        let isTrafficMode: Bool
    }
    
    static func render(_ input: Input) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0          // 840x500 pixels reais -> letras nítidas
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        
        return renderer.image { ctx in
            draw(input, in: ctx.cgContext)
        }
    }
    
    // MARK: - Desenho
    
    private static func draw(_ input: Input, in cg: CGContext) {
        let verdict = input.verdict
        let w = canvasSize.width
        let h = canvasSize.height
        let statusColor = color(for: verdict.status)
        
        // Fundo escuro automotivo
        UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1).setFill()
        cg.fill(CGRect(origin: .zero, size: canvasSize))
        
        // 1. FAIXA DO TOPO (semáforo + veredito + nota do passageiro)
        let headerH: CGFloat = 50
        statusColor.setFill()
        cg.fill(CGRect(x: 0, y: 0, width: w, height: headerH))
        
        var rightBadge: String
        if let badge = verdict.passengerBadge {
            rightBadge = badge
        } else {
            rightBadge = "META R$\(Int(input.metaAtual))/\(Int(input.metaTotal))"
        }
        if verdict.isCashPayment { rightBadge = "💵 " + rightBadge }
        if input.isTrafficMode && verdict.status == .waiting { rightBadge = "🌧 " + rightBadge }
        
        let badgeFont = roundedFont(15, .black)
        let badgeTextW = min(190, (rightBadge as NSString).size(withAttributes: [.font: badgeFont]).width + 16)
        let badgeRect = CGRect(x: w - badgeTextW - 10, y: 11, width: badgeTextW, height: 28)
        UIColor.black.withAlphaComponent(0.35).setFill()
        UIBezierPath(roundedRect: badgeRect, cornerRadius: 7).fill()
        drawFitted(rightBadge, in: badgeRect.insetBy(dx: 6, dy: 0), size: 15, minSize: 10, weight: .black, color: .white, align: .center)
        
        drawFitted(verdict.message,
                   in: CGRect(x: 14, y: 0, width: badgeRect.minX - 22, height: headerH),
                   size: 21, minSize: 12, weight: .black, color: .white, align: .left)
        
        // 2. OS 3 BLOCOS GIGANTES (R$/KM | R$/HORA | LUCRO LIVRE)
        let footerH: CGFloat = 40
        let boxTop = headerH + 10
        let boxH = h - headerH - footerH - 20
        let gap: CGFloat = 10
        let side: CGFloat = 12
        let boxW = (w - side * 2 - gap * 2) / 3
        
        let boxes: [(String, String)]
        let boxColor: UIColor
        if verdict.status == .waiting {
            boxColor = UIColor(red: 0.25, green: 0.32, blue: 0.40, alpha: 1)
            boxes = [
                ("META R$/KM", "R$ " + brl(input.minGanhoKm) + "+"),
                ("META R$/H", "R$ \(Int(input.minGanhoHora))+"),
                ("HOJE LÍQ.", "R$ \(Int(input.metaAtual))")
            ]
        } else {
            boxColor = statusColor
            boxes = [
                ("R$ / KM", verdict.ganhoPorKmText),
                ("R$ / HORA", verdict.ganhoPorHoraText),
                ("LUCRO LIVRE", verdict.lucroLiquidoText)
            ]
        }
        
        for (i, box) in boxes.enumerated() {
            let rect = CGRect(x: side + CGFloat(i) * (boxW + gap), y: boxTop, width: boxW, height: boxH)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            boxColor.withAlphaComponent(0.24).setFill()
            path.fill()
            boxColor.setStroke()
            path.lineWidth = 2.5
            path.stroke()
            
            drawFitted(box.0, in: CGRect(x: rect.minX + 4, y: rect.minY + 10, width: rect.width - 8, height: 18),
                       size: 13, minSize: 9, weight: .heavy, color: UIColor.white.withAlphaComponent(0.78), align: .center)
            drawFitted(box.1, in: CGRect(x: rect.minX + 4, y: rect.minY + 32, width: rect.width - 8, height: rect.height - 40),
                       size: 30, minSize: 14, weight: .black, color: .white, align: .center)
        }
        
        // 3. RODAPÉ (tempo/distância/busca + destino)
        let footerRect = CGRect(x: 0, y: h - footerH, width: w, height: footerH)
        UIColor.black.withAlphaComponent(0.6).setFill()
        cg.fill(footerRect)
        drawFitted(verdict.tempoEDistanciaText,
                   in: CGRect(x: 12, y: footerRect.minY, width: w * 0.55 - 12, height: footerH),
                   size: 14, minSize: 9, weight: .heavy, color: .white, align: .left)
        drawFitted(verdict.rotaResumoText,
                   in: CGRect(x: w * 0.55 + 4, y: footerRect.minY, width: w * 0.45 - 16, height: footerH),
                   size: 14, minSize: 9, weight: .bold, color: UIColor.cyan, align: .right)
        
        // Borda grossa na cor do semáforo (estilo GigU)
        statusColor.setStroke()
        let border = UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize).insetBy(dx: 3, dy: 3))
        border.lineWidth = 6
        border.stroke()
    }
    
    // MARK: - Helpers
    
    static func color(for status: VerdictStatus) -> UIColor {
        switch status {
        case .approved:  return UIColor(red: 0.06, green: 0.68, blue: 0.28, alpha: 1)
        case .goingHome: return UIColor(red: 0.06, green: 0.48, blue: 0.82, alpha: 1)
        case .warning:   return UIColor(red: 0.88, green: 0.52, blue: 0.04, alpha: 1)
        case .rejected:  return UIColor(red: 0.86, green: 0.14, blue: 0.16, alpha: 1)
        case .waiting:   return UIColor(red: 0.14, green: 0.18, blue: 0.24, alpha: 1)
        }
    }
    
    private static func brl(_ v: Double) -> String {
        String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }
    
    private static func roundedFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: desc, size: size)
        }
        return base
    }
    
    /// Desenha o texto numa linha, reduzindo a fonte até caber na largura, centralizado verticalmente
    private static func drawFitted(
        _ text: String,
        in rect: CGRect,
        size: CGFloat,
        minSize: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        align: NSTextAlignment
    ) {
        guard !text.isEmpty, rect.width > 0 else { return }
        var fontSize = size
        var font = roundedFont(fontSize, weight)
        var textSize = (text as NSString).size(withAttributes: [.font: font])
        while (textSize.width > rect.width || textSize.height > rect.height) && fontSize > minSize {
            fontSize -= 1
            font = roundedFont(fontSize, weight)
            textSize = (text as NSString).size(withAttributes: [.font: font])
        }
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byTruncatingTail
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.midY - textSize.height / 2,
            width: rect.width,
            height: textSize.height
        )
        (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
    }
}
