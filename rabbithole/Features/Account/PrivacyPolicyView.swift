import SwiftUI

/// Placeholder for the privacy policy. Replace with the final text (or a hosted URL)
/// before release – this summary only describes what the app actually stores.
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                Text("Návrh – finální znění zásad ochrany osobních údajů doplníme před vydáním.")
                    .foregroundStyle(.secondary)
            }

            Section("Co zůstává jen v zařízení") {
                Text("Vybraná témata a jejich váhy, historie zobrazených článků, doba čtení a uložené články (pokud nemáš účet).")
            }

            Section("Co ukládáme na server, když máš účet") {
                Text("Přezdívku, avatar, vybraná témata, seznam přátel a blokovaných uživatelů, články, které posíláš přátelům, a zprávy k nim. Uložené články jen tehdy, když povolíš, aby je přátelé viděli.")
                Text("K přihlášení používáme e-mail nebo účet Google. E-mail neukazujeme ostatním uživatelům.")
            }

            Section("Kdo data vidí") {
                Text("Přezdívku a avatar vidí ostatní přihlášení uživatelé (kromě těch, které blokuješ). Témata a uložené články jen tví přátelé, zprávy jen účastníci konverzace.")
            }

            Section("Smazání") {
                Text("Účet můžeš kdykoli smazat přímo v aplikaci. Smažou se tím všechna data na serveru, včetně tvých zpráv.")
            }

            Section("Zpracovatel") {
                Text("Data jsou uložena u služby Supabase v datovém centru v EU (Irsko).")
            }
        }
        .navigationTitle("Ochrana soukromí")
        .navigationBarTitleDisplayMode(.inline)
    }
}
