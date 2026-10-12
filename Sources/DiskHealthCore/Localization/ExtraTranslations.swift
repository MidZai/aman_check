import Foundation

public struct ExtraTranslations {
    public static func lookup(english: String, french: String, language: AppLanguage) -> String? {
        let dict: [String: String]?
        switch language {
        case .zhHans: dict = zhHans
        case .zhHant: dict = zhHant
        case .korean: dict = korean
        case .arabic: dict = arabic
        case .portuguese: dict = portuguese
        case .spanish: dict = spanish
        case .german: dict = german
        case .italian: dict = italian
        case .japanese: dict = japanese
        case .russian: dict = russian
        case .turkish: dict = turkish
        case .dutch: dict = dutch
        case .polish: dict = polish
        case .hindi: dict = hindi
        case .vietnamese: dict = vietnamese
        case .ukrainian: dict = ukrainian
        default: return nil
        }
        
        if let exact = dict?[english] ?? dict?[french] {
            return exact
        }
        
        let trimmedEn = english.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFr = french.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = dict?[trimmedEn] ?? dict?[trimmedFr] {
            return exact
        }
        
        return dynamicMatch(english: english, french: french, language: language)
    }

    private static func dynamicMatch(english: String, french: String, language: AppLanguage) -> String? {
        // Pattern matches for dynamic templates
        if english.starts(with: "The drive refused the command (code ") && english.hasSuffix("). Try again; if the problem persists, export a diagnostic.") {
            let code = english.replacingOccurrences(of: "The drive refused the command (code ", with: "")
                              .replacingOccurrences(of: "). Try again; if the problem persists, export a diagnostic.", with: "")
            switch language {
            case .zhHans: return "驱动器拒绝了命令（代码 \(code)）。请重试；如果问题仍然存在，请导出诊断报告。"
            case .zhHant: return "磁碟機拒絕了指令（代碼 \(code)）。請重試；若問題持續，請匯出診斷報告。"
            case .korean: return "드라이브가 명령을 거부했습니다(코드 \(code)). 다시 시도하십시오. 문제가 지속되면 진단을 내보내십시오."
            case .arabic: return "رفض محرك الأقراص الأمر (الرمز \(code)). أعد المحاولة، وإذا استمرت المشكلة، فقم بتصدير تقرير التشخيص."
            case .portuguese: return "A unidade recusou o comando (código \(code)). Tente novamente; se o problema persistir, exporte um diagnóstico."
            case .spanish: return "La unidad rechazó el comando (código \(code)). Intente de nuevo; si el problema persiste, exporte un diagnóstico."
            case .german: return "Das Laufwerk hat den Befehl abgelehnt (Code \(code)). Versuchen Sie es erneut; wenn das Problem weiterhin besteht, exportieren Sie eine Diagnose."
            case .italian: return "L'unità ha rifiutato il comando (codice \(code)). Riprova; se il problema persiste, esporta una diagnosi."
            case .japanese: return "ドライブがコマンドを拒否しました (コード \(code))。再試行してください。問題が解決しない場合は診断をエクスポートしてください。"
            case .russian: return "Диск отклонил команду (код \(code)). Повторите попытку; если проблема сохраняется, экспортируйте диагностику."
            case .turkish: return "Sürücü komutu reddetti (kod \(code)). Tekrar deneyin; sorun devam ederse bir tanı raporu dışa aktarın."
            case .dutch: return "De schijf weigerde de opdracht (code \(code)). Probeer het opnieuw; als het probleem aanhoudt, exporteer dan een diagnose."
            case .polish: return "Dysk odrzucił polecenie (kod \(code)). Spróbuj ponownie; jeśli problem będzie się powtarzał, wyeksportuj diagnostykę."
            case .hindi: return "ड्राइव ने कमांड को अस्वीकार कर दिया (कोड \(code))। पुनः प्रयास करें; यदि समस्या बनी रहती है, तो डायग्नोस्टिक निर्यात करें।"
            case .vietnamese: return "Ổ đĩa đã từ chối lệnh (mã \(code)). Thử lại; nếu sự cố vẫn tiếp diễn, hãy xuất chẩn đoán."
            case .ukrainian: return "Диск відхилив команду (код \(code)). Спробуйте ще раз; якщо проблема не зникає, експортуйте діагностику."
            default: return nil
            }
        }
        
        if english.starts(with: "Reading health data failed (") && english.hasSuffix("). Try again; if the problem persists, export a diagnostic.") {
            let code = english.replacingOccurrences(of: "Reading health data failed (", with: "")
                              .replacingOccurrences(of: "). Try again; if the problem persists, export a diagnostic.", with: "")
            switch language {
            case .zhHans: return "读取健康数据失败（\(code)）。请重试；如果问题仍然存在，请导出诊断报告。"
            case .zhHant: return "讀取健康資料失敗（\(code)）。請重試；若問題持續，請匯出診斷報告。"
            case .korean: return "건강 데이터 읽기 실패(\(code)). 다시 시도하십시오. 문제가 지속되면 진단을 내보내십시오."
            case .arabic: return "فشلت قراءة بيانات الصحة (\(code)). أعد المحاولة، وإذا استمرت المشكلة، فقم بتصدير تقرير التشخيص."
            case .portuguese: return "Falha ao ler os dados de integridade (\(code)). Tente novamente; se o problema persistir, exporte um diagnóstico."
            case .spanish: return "Error al leer datos de salud (\(code)). Intente de nuevo; si el problema persiste, exporte un diagnóstico."
            case .german: return "Lesen der Zustandsdaten fehlgeschlagen (\(code)). Versuchen Sie es erneut; wenn das Problem weiterhin besteht, exportieren Sie eine Diagnose."
            case .italian: return "Lettura dei dati di integrità non riuscita (\(code)). Riprova; se il problema persiste, esporta una diagnosi."
            case .japanese: return "健康データの読み取りに失敗しました (\(code))。再試行してください。問題が解決しない場合は診断をエクスポートしてください。"
            case .russian: return "Сбой чтения данных о состоянии (\(code)). Повторите попытку; если проблема сохраняется, экспортируйте диагностику."
            case .turkish: return "Sağlık verileri okunamadı (\(code)). Tekrar deneyin; sorun devam ederse bir tanı raporu dışa aktarın."
            case .dutch: return "Gezondheidsgegevens lezen mislukt (\(code)). Probeer het opnieuw; als het probleem aanhoudt, exporteer dan een diagnose."
            case .polish: return "Odczyt danych o stanie nie powiódł się (\(code)). Spróbuj ponownie; jeśli problem będzie się powtarzał, wyeksportuj diagnostykę."
            case .hindi: return "स्वास्थ्य डेटा पढ़ना विफल रहा (\(code))। पुनः प्रयास करें; यदि समस्या बनी रहती है, तो डायग्नोस्टिक निर्यात करें।"
            case .vietnamese: return "Đọc dữ liệu sức khỏe thất bại (\(code)). Thử lại; nếu sự cố vẫn tiếp diễn, hãy xuất chẩn đoán."
            case .ukrainian: return "Не вдалося зчитати дані про стан (\(code)). Спробуйте ще раз; якщо проблема не зникає, експортуйте діагностику."
            default: return nil
            }
        }

        if english.starts(with: "Unknown chip (") && english.hasSuffix(")") {
            let hex = String(english.dropFirst("Unknown chip (".count).dropLast())
            switch language {
            case .zhHans: return "未知芯片（\(hex)）"
            case .zhHant: return "未知晶片（\(hex)）"
            case .korean: return "알 수 없는 칩(\(hex))"
            case .arabic: return "شريحة غير معروفة (\(hex))"
            case .portuguese: return "Chip desconhecido (\(hex))"
            case .spanish: return "Chip desconocido (\(hex))"
            case .german: return "Unbekannter Chip (\(hex))"
            case .italian: return "Chip sconosciuto (\(hex))"
            case .japanese: return "不明なチップ (\(hex))"
            case .russian: return "Неизвестный чип (\(hex))"
            case .turkish: return "Bilinmeyen çip (\(hex))"
            case .dutch: return "Onbekende chip (\(hex))"
            case .polish: return "Nieznany układ scalony (\(hex))"
            case .hindi: return "अज्ञात चिप (\(hex))"
            case .vietnamese: return "Chip không xác định (\(hex))"
            case .ukrainian: return "Невідомий чип (\(hex))"
            default: return nil
            }
        }

        if english.hasSuffix(" free") {
            let amount = String(english.dropLast(" free".count))
            switch language {
            case .zhHans: return "\(amount) 可用"
            case .zhHant: return "\(amount) 可用"
            case .korean: return "\(amount) 여유"
            case .arabic: return "\(amount) متوفر"
            case .portuguese: return "\(amount) livres"
            case .spanish: return "\(amount) libres"
            case .german: return "\(amount) frei"
            case .italian: return "\(amount) liberi"
            case .japanese: return "\(amount) 空き"
            case .russian: return "\(amount) свободно"
            case .turkish: return "\(amount) boş"
            case .dutch: return "\(amount) vrij"
            case .polish: return "\(amount) wolne"
            case .hindi: return "\(amount) खाली"
            case .vietnamese: return "\(amount) khả dụng"
            case .ukrainian: return "\(amount) вільно"
            default: return nil
            }
        }
        
        return nil
    }
}
