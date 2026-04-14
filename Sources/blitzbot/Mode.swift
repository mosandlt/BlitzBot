import Foundation

enum Mode: String, CaseIterable, Identifiable, Codable {
    case normal, business, plus, rage, emoji

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal:   return String(localized: "mode.normal.name", defaultValue: "Normal")
        case .business: return String(localized: "mode.business.name", defaultValue: "Business")
        case .plus:     return String(localized: "mode.plus.name", defaultValue: "Plus")
        case .rage:     return String(localized: "mode.rage.name", defaultValue: "Rage")
        case .emoji:    return String(localized: "mode.emoji.name", defaultValue: "Emoji")
        }
    }

    var tagline: String {
        switch self {
        case .normal:   return String(localized: "mode.normal.tagline", defaultValue: "Sprache rein. Text raus.")
        case .business: return String(localized: "mode.business.tagline", defaultValue: "Sprache rein. Businesstauglich raus.")
        case .plus:     return String(localized: "mode.plus.tagline", defaultValue: "Geschrieben sprechen.")
        case .rage:     return String(localized: "mode.rage.tagline", defaultValue: "Frust rein. Entspannt raus.")
        case .emoji:    return String(localized: "mode.emoji.tagline", defaultValue: "Sprache rein. Text mit Emojis raus.")
        }
    }

    var symbolName: String {
        switch self {
        case .normal:   return "mic.fill"
        case .business: return "briefcase.fill"
        case .plus:     return "text.justify.left"
        case .rage:     return "flame.fill"
        case .emoji:    return "face.smiling"
        }
    }

    var defaultSystemPrompt: String {
        switch self {
        case .normal:
            return ""
        case .business:
            return """
            Du bekommst einen diktierten deutschen Text. Formuliere ihn für geschäftliche Kommunikation \
            (Mail, Meeting, Kunde, LinkedIn): klar, höflich, strukturiert, aktiv formuliert, ohne Floskeln. \
            Behalte Aussage und Fakten vollständig. Ergänze bei Bedarf eine kurze Anrede/Abschluss nur wenn \
            der User sie diktiert hat — erfinde keine. Vermeide übertriebenes Marketingdeutsch. \
            Antworte ausschließlich mit dem finalen Text, ohne Einleitung.
            """
        case .plus:
            return """
            Du bekommst einen diktierten deutschen Text. Deine Aufgabe: minimal aufräumen, \
            nicht umschreiben. Entferne nur offensichtliche Füllwörter (ähm, also, halt, ne, sozusagen) \
            und korrigiere Satzbau/Grammatik, wo er im Gesprochenen noch holprig ist. \
            Behalte: Wortwahl, Tonalität, Persönlichkeit, Aussage, Reihenfolge der Sätze. \
            Ändere nicht: Stil in Richtung Business oder formeller. Der Text soll nach dem User klingen, \
            nicht nach einem PR-Redakteur. Keine neuen Sätze, keine Zusammenfassungen, keine Einleitungen. \
            Antworte ausschließlich mit dem leicht geglätteten Text.
            """
        case .rage:
            return """
            Du bekommst eine wütend diktierte deutsche Notiz. Entschärfe sie: \
            raus mit Beleidigungen, Schimpfwörtern und aggressivem Ton — die sachliche Kritik bleibt aber \
            vollständig erhalten und darf deutlich sein. Ziel: freundlich, direkt, klar. \
            Behalte die Perspektive und Wortwahl des Users so weit wie möglich. \
            Keine Weichspülung, keine Höflichkeitsfloskeln am Anfang oder Ende. \
            Antworte ausschließlich mit dem umformulierten Text.
            """
        case .emoji:
            return """
            Du bekommst einen diktierten deutschen Text. Übernimm den Wortlaut 1:1 (minimale Glättung \
            bei offensichtlichen Füllwörtern ist ok), und füge an passenden Stellen dezent Emojis ein. \
            Richtwert: 1 Emoji pro 1-2 Sätze. Keine Umformulierung, kein Umbau. \
            Antworte ausschließlich mit dem Text inklusive Emojis.
            """
        }
    }
}
