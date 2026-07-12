import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: ""
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        }
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if identifier.hasPrefix("zh-hant") || identifier.hasPrefix("zh-tw") || identifier.hasPrefix("zh-hk") {
            return .traditionalChinese
        }
        if identifier.hasPrefix("zh") { return .simplifiedChinese }
        if identifier.hasPrefix("ja") { return .japanese }
        if identifier.hasPrefix("ko") { return .korean }
        if identifier.hasPrefix("fr") { return .french }
        if identifier.hasPrefix("de") { return .german }
        if identifier.hasPrefix("es") { return .spanish }
        return .english
    }

    var localeIdentifier: String { resolved.rawValue }
}

enum L10nKey: String, Sendable {
    case settingsWindowTitle
    case settingsSubtitle
    case refreshMenuBarItems
    case settings
    case collapseSecondRow
    case expandSecondRow
    case accessibilityRequired
    case authorize
    case noFoldedItems
    case choose
    case showDiagnosticLog
    case refresh
    case language
    case followSystem
    case launchAtLogin
    case ok
    case accessibilityExplanation
    case requestPermission
    case openSystemSettings
    case lockedFirstRowHelp
    case lockedFirstRowAccessibility
    case showInFirstRow
    case settingsEllipsis
    case quitBarFold
    case errorMoveFailed
    case errorOpenRetry
    case errorOpenNoApplication
}

enum L10n {
    static func string(_ key: L10nKey, language: AppLanguage) -> String {
        let resolved = language.resolved
        return translations[key]?[resolved]
            ?? translations[key]?[.english]
            ?? key.rawValue
    }

    static func format(
        _ key: L10nKey,
        language: AppLanguage,
        arguments: [CVarArg]
    ) -> String {
        String(
            format: string(key, language: language),
            locale: Locale(identifier: language.localeIdentifier),
            arguments: arguments
        )
    }

    private static let translations: [L10nKey: [AppLanguage: String]] = [
        .settingsWindowTitle: values(
            "BarFold 设置", "BarFold 設定", "BarFold Settings", "BarFold 設定", "BarFold 설정",
            "Réglages de BarFold", "BarFold-Einstellungen", "Ajustes de BarFold"
        ),
        .settingsSubtitle: values(
            "选择保留在菜单栏第一行的项目", "選擇保留在選單列第一列的項目",
            "Choose items to keep in the first menu bar row", "メニューバーの1行目に残す項目を選択",
            "메뉴 막대 첫 번째 줄에 유지할 항목 선택", "Choisissez les éléments à conserver sur la première ligne",
            "Elemente für die erste Menüleistenzeile auswählen", "Elige los elementos que se mantienen en la primera fila"
        ),
        .refreshMenuBarItems: values(
            "刷新菜单栏项目", "重新整理選單列項目", "Refresh menu bar items", "メニューバー項目を更新",
            "메뉴 막대 항목 새로 고침", "Actualiser les éléments de la barre des menus",
            "Menüleistenelemente aktualisieren", "Actualizar elementos de la barra de menús"
        ),
        .settings: values("设置", "設定", "Settings", "設定", "설정", "Réglages", "Einstellungen", "Ajustes"),
        .collapseSecondRow: values(
            "收起第二行", "收合第二列", "Collapse second row", "2行目を折りたたむ", "두 번째 줄 접기",
            "Replier la deuxième ligne", "Zweite Zeile einklappen", "Contraer la segunda fila"
        ),
        .expandSecondRow: values(
            "展开第二行", "展開第二列", "Expand second row", "2行目を展開", "두 번째 줄 펼치기",
            "Déplier la deuxième ligne", "Zweite Zeile ausklappen", "Expandir la segunda fila"
        ),
        .accessibilityRequired: values(
            "需要辅助功能权限", "需要輔助使用權限", "Accessibility permission required", "アクセシビリティ権限が必要です",
            "손쉬운 사용 권한 필요", "Autorisation d'accessibilité requise", "Bedienungshilfen-Berechtigung erforderlich",
            "Se requiere permiso de accesibilidad"
        ),
        .authorize: values("授权", "授權", "Authorize", "許可", "권한 부여", "Autoriser", "Autorisieren", "Autorizar"),
        .noFoldedItems: values(
            "暂无折叠项目", "沒有收合項目", "No folded items", "折りたたまれた項目はありません",
            "접힌 항목 없음", "Aucun élément replié", "Keine eingeklappten Elemente", "No hay elementos contraídos"
        ),
        .choose: values("选择", "選取", "Choose", "選択", "선택", "Choisir", "Auswählen", "Elegir"),
        .showDiagnosticLog: values(
            "显示诊断日志", "顯示診斷記錄", "Show diagnostic log", "診断ログを表示", "진단 로그 보기",
            "Afficher le journal de diagnostic", "Diagnoseprotokoll anzeigen", "Mostrar registro de diagnóstico"
        ),
        .refresh: values("刷新", "重新整理", "Refresh", "更新", "새로 고침", "Actualiser", "Aktualisieren", "Actualizar"),
        .language: values("语言", "語言", "Language", "言語", "언어", "Langue", "Sprache", "Idioma"),
        .followSystem: values(
            "跟随系统", "跟隨系統", "Follow System", "システム設定に従う", "시스템 설정 따르기",
            "Suivre le système", "Systemeinstellung verwenden", "Seguir el sistema"
        ),
        .launchAtLogin: values(
            "登录时启动", "登入時啟動", "Launch at login", "ログイン時に起動", "로그인 시 실행",
            "Lancer à l'ouverture de session", "Bei der Anmeldung starten", "Abrir al iniciar sesión"
        ),
        .ok: values("好", "好", "OK", "OK", "확인", "OK", "OK", "Aceptar"),
        .accessibilityExplanation: values(
            "BarFold 通过辅助功能读取、重排并打开菜单栏项目。",
            "BarFold 使用輔助使用權限讀取、重新排列及開啟選單列項目。",
            "BarFold uses Accessibility to read, reorder, and open menu bar items.",
            "BarFoldはアクセシビリティを使用してメニューバー項目を読み取り、並べ替え、開きます。",
            "BarFold는 손쉬운 사용 권한으로 메뉴 막대 항목을 읽고 재정렬하고 엽니다.",
            "BarFold utilise l'accessibilité pour lire, réordonner et ouvrir les éléments de la barre des menus.",
            "BarFold verwendet Bedienungshilfen, um Menüleistenelemente zu lesen, zu sortieren und zu öffnen.",
            "BarFold usa Accesibilidad para leer, reordenar y abrir elementos de la barra de menús."
        ),
        .requestPermission: values(
            "请求权限", "要求權限", "Request Permission", "権限を要求", "권한 요청",
            "Demander l'autorisation", "Berechtigung anfordern", "Solicitar permiso"
        ),
        .openSystemSettings: values(
            "打开系统设置", "開啟系統設定", "Open System Settings", "システム設定を開く", "시스템 설정 열기",
            "Ouvrir les réglages système", "Systemeinstellungen öffnen", "Abrir Ajustes del Sistema"
        ),
        .lockedFirstRowHelp: values(
            "macOS 固定在第一行，无法移动", "macOS 固定在第一列，無法移動",
            "macOS keeps this in the first row; it cannot be moved", "macOSにより1行目に固定されているため移動できません",
            "macOS가 첫 번째 줄에 고정하므로 이동할 수 없습니다", "macOS le conserve sur la première ligne; impossible de le déplacer",
            "macOS hält dieses Element in der ersten Zeile; es kann nicht verschoben werden",
            "macOS lo mantiene en la primera fila y no se puede mover"
        ),
        .lockedFirstRowAccessibility: values(
            "固定在第一行，无法移动", "固定在第一列，無法移動", "Locked in the first row; cannot be moved",
            "1行目に固定されているため移動できません", "첫 번째 줄에 고정되어 이동할 수 없음",
            "Verrouillé sur la première ligne; impossible à déplacer", "In der ersten Zeile gesperrt; nicht verschiebbar",
            "Bloqueado en la primera fila; no se puede mover"
        ),
        .showInFirstRow: values(
            "显示在第一行", "顯示在第一列", "Show in first row", "1行目に表示", "첫 번째 줄에 표시",
            "Afficher sur la première ligne", "In der ersten Zeile anzeigen", "Mostrar en la primera fila"
        ),
        .settingsEllipsis: values("设置…", "設定…", "Settings...", "設定…", "설정…", "Réglages...", "Einstellungen...", "Ajustes..."),
        .quitBarFold: values(
            "退出 BarFold", "結束 BarFold", "Quit BarFold", "BarFoldを終了", "BarFold 종료",
            "Quitter BarFold", "BarFold beenden", "Salir de BarFold"
        ),
        .errorMoveFailed: values(
            "无法移动“%@”。该项目可能不支持菜单栏重排。",
            "無法移動「%@」。此項目可能不支援選單列重新排列。",
            "Could not move \"%@\". This item may not support menu bar reordering.",
            "「%@」を移動できません。この項目はメニューバーの並べ替えに対応していない可能性があります。",
            "\"%@\" 항목을 이동할 수 없습니다. 메뉴 막대 재정렬을 지원하지 않을 수 있습니다.",
            "Impossible de déplacer \"%@\". Cet élément ne prend peut-être pas en charge la réorganisation.",
            "\"%@\" konnte nicht verschoben werden. Dieses Element unterstützt möglicherweise keine Neuanordnung.",
            "No se pudo mover \"%@\". Es posible que este elemento no admita la reorganización."
        ),
        .errorOpenRetry: values(
            "无法打开“%@”。请刷新后重试。", "無法開啟「%@」。請重新整理後再試。",
            "Could not open \"%@\". Refresh and try again.", "「%@」を開けません。更新してもう一度お試しください。",
            "\"%@\" 항목을 열 수 없습니다. 새로 고친 후 다시 시도하세요.",
            "Impossible d'ouvrir \"%@\". Actualisez puis réessayez.",
            "\"%@\" konnte nicht geöffnet werden. Aktualisieren Sie und versuchen Sie es erneut.",
            "No se pudo abrir \"%@\". Actualiza e inténtalo de nuevo."
        ),
        .errorOpenNoApplication: values(
            "无法打开“%@”。该菜单栏项目没有可打开的应用。",
            "無法開啟「%@」。此選單列項目沒有可開啟的應用程式。",
            "Could not open \"%@\". This menu bar item has no application that can be opened.",
            "「%@」を開けません。このメニューバー項目には開くことのできるアプリがありません。",
            "\"%@\" 항목을 열 수 없습니다. 이 메뉴 막대 항목에는 열 수 있는 앱이 없습니다.",
            "Impossible d'ouvrir \"%@\". Cet élément n'a aucune application pouvant être ouverte.",
            "\"%@\" konnte nicht geöffnet werden. Für dieses Menüleistenelement ist keine App verfügbar.",
            "No se pudo abrir \"%@\". Este elemento no tiene una aplicación que se pueda abrir."
        )
    ]

    private static func values(
        _ simplifiedChinese: String,
        _ traditionalChinese: String,
        _ english: String,
        _ japanese: String,
        _ korean: String,
        _ french: String,
        _ german: String,
        _ spanish: String
    ) -> [AppLanguage: String] {
        [
            .simplifiedChinese: simplifiedChinese,
            .traditionalChinese: traditionalChinese,
            .english: english,
            .japanese: japanese,
            .korean: korean,
            .french: french,
            .german: german,
            .spanish: spanish
        ]
    }
}
