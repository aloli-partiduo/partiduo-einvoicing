# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

# Traductions des écrans de l'extension (ADR-005 D7) : chaque route de
# `/ext/EINV/` servie en `GET` (liste tirée du routeur de Marten), obtenue
# dans chaque langue de l'interface par un administrateur, plateforme
# raccordée, sur des factures émises (à transmettre, transmise et déposée,
# hors plateforme), des factures reçues (UBL et CII à traiter,
# pré-comptabilisée, refusée) et un annuaire garni. Contrôle de l'interface
# (`PartiduoUi::Translations`) : ni marqueur de traduction absente, ni clé
# brute, ni interpolation non résolue, et toute route atteinte par les liens
# des pages.

private alias S = Einvoicing::SpecSupport
private alias Api = Einvoicing::Api

describe "Traductions des écrans de la facturation électronique (chaque langue de l'interface)" do
  it "rend chaque écran dans chaque langue, sans clé absente, brute ni interpolation non résolue" do
    browser = S.signed_in
    sent = S.issue
    Api.transmit(S.admin, S.transmission(sent).id).value!
    S.platform.acknowledge(S.platform.sent("CustomerInvoice").first, "Ok")
    S.issue(channel: "paper")
    S.supplier
    S.platform.deliver(S.ubl_invoice, "FM-2026-0412.xml", "UBL")
    S.platform.deliver(S.ubl_invoice("FM-2026-0413"), "FM-2026-0413.xml", "UBL")
    S.platform.deliver(S.ubl_invoice("FM-2026-0414"), "FM-2026-0414.xml", "UBL")
    S.platform.deliver(S.cii_invoice, "PB-7781.xml", "CII")
    browser.post("/ext/EINV/sync", {"next" => "/ext/EINV/incoming"}).status.should eq(302)
    receptions = Api.receptions(S.admin).to_h { |view| {view.number, view.id} }
    browser.post("/ext/EINV/incoming/#{receptions["FM-2026-0412"]}/post").status.should eq(302)
    browser.post("/ext/EINV/incoming/#{receptions["FM-2026-0413"]}/refuse", {"reason_code" => "DOUBLON", "reason" => "reçue deux fois"}).status.should eq(302)
    # Facture à transmettre, émise après le relevé (qui l'aurait transmise).
    S.issue
    S.platform.directory << JSON.parse({"addressingIdentifier" => S::CUSTOMER_SIREN, "siren" => S::CUSTOMER_SIREN,
                                        "platformType" => "WK", "directoryLineStatus" => "Enabled",
                                        "legalUnit" => {"businessName" => "Atelier Morel SAS"}}.to_json).as_h

    explorer = PartiduoUi::Translations::Explorer.new(&.name.starts_with?("einv:"))
    # Graine : résultats de l'annuaire (formulaire de recherche, sans lien).
    explorer.crawl(browser, "EINV", ["/ext/EINV/directory?q=#{S::CUSTOMER_SIREN}"])
    puts "\nTraductions de EINV : #{explorer.report}"
    (explorer.failures + explorer.unreached.map { |route| "route jamais atteinte : #{route}" }).should eq([] of String)
  ensure
    # L'exploration laisse active la dernière langue demandée (nl) : les
    # exemples suivants attendent la langue par défaut.
    I18n.activate(Marten.settings.i18n.default_locale)
  end
end
