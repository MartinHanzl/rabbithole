import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Rabbithole")
                        .font(.readingTitle(.title))
                    Text("Krátké a zajímavé články podle tvých zájmů místo nekonečného scrollování.")
                        .foregroundStyle(.secondary)
                    Text("Verze \(AppConfig.appVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Texty článků pocházejí z české Wikipedie a jsou dostupné pod licencí Creative Commons Uveďte původ – Zachovejte licenci 4.0 (CC BY-SA 4.0). U každého článku je uveden odkaz na původní stránku, kde najdeš i seznam autorů a historii úprav.")
                Link(destination: WikipediaURLs.license) {
                    Label("Znění licence CC BY-SA 4.0", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://cs.wikipedia.org/wiki/Wikipedie:Licence_Creative_Commons_Uveďte_původ-Zachovejte_licenci_4.0")!) {
                    Label("Licenční podmínky Wikipedie", systemImage: "doc.text")
                }
            } header: {
                Text("Texty")
            }

            Section {
                Text("Obrázky mají vlastní licence a autory. U každého obrázku najdeš odkaz „Obrázek: autor a licence“, který vede na jeho stránku na Wikimedia Commons nebo Wikipedii s úplnými údaji.")
            } header: {
                Text("Obrázky")
            }

            Section {
                Text("Obsah se načítá přes veřejná API Wikimedia (REST API a Action API české Wikipedie). Odpovědi se ukládají do mezipaměti v zařízení, aby aplikace zbytečně nezatěžovala servery.")
                Text("Wikipedie® je ochranná známka nadace Wikimedia Foundation. Tato aplikace není s nadací Wikimedia Foundation nijak spojena.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Zdroj dat")
            }

            Section {
                Text("Vybraná témata, uložené články a historie zobrazených článků zůstávají jen v tomto zařízení. Aplikace nemá účty a nesbírá žádná osobní data.")
            } header: {
                Text("Soukromí")
            }
        }
        .navigationTitle("O aplikaci a licence")
        .navigationBarTitleDisplayMode(.inline)
    }
}
