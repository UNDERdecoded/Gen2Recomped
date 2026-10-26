# Automatische Testcache-Bereinigung

Die Python-QA-Starter und `tools/perf/run_*.command` verwenden `tools/qa_storage.py`.
Die Bereinigung läuft vor neuen Testschritten und beim Beenden; es ist kein
zusätzlicher täglicher Hintergrundjob nötig.

Alle beteiligten Worktrees teilen folgende Grenzen für unbenutzte Daten:

| Daten | Grenze |
| --- | --- |
| Erzeugte ROM-Importkopien und installierte Origami-Testmodkopien | 2 GiB insgesamt |
| Geometrie-Payloads unter `.local/qa` | 4 GiB insgesamt |
| Exportierte QA-Engines, Mod-ZIPs und zusätzliche Referenz-/Testkopien | 4 GiB gemeinsam |
| Kompilierter ULA-Cache in eigenen QA-Profilen | 2 GiB insgesamt |
| Aufbewahrung unbenutzter Cache-Kopien | höchstens 24 Stunden |
| Freier Speicher vor neuen Testschritten und während eigener Kindprozesse | mindestens 20 GiB |

Die ältesten unbenutzten Gruppen werden zuerst entfernt, sobald Alter oder
Budget überschritten werden. Aktive Daten und Eingaben sind durch gemeinsame
OS-Dateisperren geschützt. Kindprozesse erben diese Sperren. Auch ältere Starter,
die nur die gesamte QA-Gruppe sperren, schützen ihre Engine-Kopien. Eine als
Eingabe gesperrte QA-Identity schützt auch den zugehörigen Engine-Snapshot.
Bereits laufende ältere Programme übernehmen neue Regeln erst beim Neustart.

## Erhaltene Daten und Quellarchiv

Quellcode-Repositories, originale Modelle, Spielerprofile, Spielstände, Optionen,
ROM-Originale und Imports unter `baseroms` bleiben erhalten. Ebenso verbleiben
QA-Berichte, Logs, Treiber, Vergleichsbilder und `index.data` an ihrem Ort.
Beliebige fremde Mods und echte Git-Checkouts werden nicht bereinigt.

Nur eigene `oasc-…-qa-…`-Profile sind für Import-/Testmodbereinigung zugelassen.
Bei Testmods werden ausschließlich echte Installationsordner mit passender
Manifest-ID `ORIGAMI_ASCENDANT_GEN2_PREP` oder `ORIGAMI_ASCENDANT` berücksichtigt.
Runtime-Kopien werden nur unter
`.local/qa/gen2-native-mod*/oasc-gen2recomp-qa-full109-…` oder
`.local/qa/gen2-edition-mod*/oasc-gen2recomp-qa-full109-…` registriert.

Vor dem Entfernen einer Testmod-/Engine-/ZIP-Kopie werden **alle enthaltenen
Quellcode- und Modellbytes** in einem lokalen, inhaltsadressierten Git-Archiv
unter `~/.local/share/origami-qa-preserved.git` gesichert. Identische Inhalte
werden nur einmal gespeichert. Eine atomar geschriebene
`qa-preserved-sources.json` im jeweiligen QA-Profil oder Laufordner nennt den
Commit jedes gesicherten Unterordners. Erst nach dauerhaftem Git-Checkpoint wird
die Arbeitskopie entfernt. Schlägt das Sichern fehl, bleibt die Kopie erhalten.
Das Quellarchiv ist dauerhaft und wird von der Cache-Bereinigung nicht gelöscht.

Wiederherstellung in einen neuen leeren Ordner:

```sh
git --git-dir="$HOME/.local/share/origami-qa-preserved.git" archive COMMIT snapshot \
  | tar -x -C /pfad/zum/leeren-ordner --strip-components=1
```

`.qa-keep` im Laufordner, Profil oder obersten `.local/qa/<gruppe>`-Ordner schützt
Kopien zusätzlich. Ein über `gen3/render-cache` installiertes Geometriepaket und
die über `.local/imports` verknüpften Importvorlagen registrierter Worktrees
bleiben geschützt. Die Nutzdaten dauerhaft erhaltener Originale und Nachweise
zählen nicht zu den löschbaren Cachebudgets.

## ULA

`qa_ula(path)` akzeptiert ausschließlich
`LOVE/ula-…-qa…/modstorage/german_rom_source/compiled`. Es löscht keine Dateien
außerhalb dieses kompilierten Caches. Der ULA-Compiler hält außerdem direkt beim
Erzeugen/Benutzen von Cache-Schlüsseln ein Limit von 2 GiB und 24 Stunden ein.
Alte Schlüssel werden zuerst entfernt. Ein einzelner übergroßer Schlüssel bleibt
nur im Speicher; die Übersetzungs-/Grafik- und Registry-Ergebnisse bleiben gleich.
Fehlgeschlagene Cache-Schreibvorgänge räumen ihre unvollständigen Nutzdaten auf.
Die Regenerierung verwendet die erhaltenen Originale und Sprachrezepte.

## Neue Teststarter

`qa_source(path)` beziehungsweise `qa_source_identity` pinnen Eingaben **vor** der
ersten Bereinigung. `qa_destination(path)` sperrt eigene Importziele **vor** dem
Kopieren. `qa_cache(path)` registriert Geometrie- und passende Runtime-Kopien.
`qa_ula(path)` sperrt einen kompilierten ULA-Testcache. `qa_run` und `qa_popen`
vererben Sperren und Speicherüberwachung. Explizite Ausgaben außerhalb der oben
beschriebenen QA-Verzeichnisse werden nicht pauschal als löschbar eingestuft.
Zusätzliche bekannte Layouts werden bei Teststarts und durch die regelmäßige
Kontrolle mit Schonzeit sicher aufgenommen; Details stehen unten.

Prüfung ohne ROM oder echte Benutzerdaten:

```sh
python3 tests/qa_storage_test.py
python3 tests/qa_extended_storage_test.py
```

## Vollständige Kopienpflege und regelmäßige Kontrolle

Die bisherigen 8 GiB freie Reserve sind auf **20 GiB** angehoben. Neue verwaltete
Tests prüfen sie vor Kopien und Prozessen; laufende eigene QA-Prozessgruppen
werden beim Unterschreiten beendet. Andere Programme werden nicht beendet.

`qa_legacy_storage.py` ergänzt die zuvor separat bereinigten Referenzkopien:
`.local/*-baseline`, `.local/baseline`, bekannte native Messordner,
`.local/engine-parity/*`, native `.local/qa/gen2recomp-qa-…/engine`, eingefrorene
QA-Referenz-/Unit-Hosts, bekannte ULA-Testmodinstallationen und ausdrücklich
benannte `dist/Origami-Ascendant-Gen2Recomped-…-candidate.zip`-Pakete.
Diese Kopien und die bisherigen Engine-/ZIP-Kopien teilen **ein** globales
Budget von **4 GiB** unbenutzter Daten und höchstens **24 Stunden** Aufbewahrung.
Erzeugte Importkopien aller elf unterstützten Editionen teilen weiter 2 GiB;
Geometrie-Payloads 4 GiB und kompilierte ULA-Testcaches 2 GiB.

Vor Entfernen werden eigenständig lesbare Quell-/Modellbytes im bestehenden
Git-Archiv gesichert. `baseroms`, ROM-Dateien, Save-Dateien, Speicherstands- und
Einstellungsverzeichnisse verbleiben vor Ort. Echte Git-Checkouts, fremde Mods,
Spielerprofile und `.qa-keep`-Teilbäume sind geschützt. Die Löschung umfasst nur
die tatsächlich gesicherten, anschließend unverändert geprüften Dateien.
Neue oder während der Sicherung veränderte Dateien bleiben erhalten.
`qa-preserved-sources.json` im übergeordneten Verzeichnis nennt den Restore-Commit;
bei teilweise erhaltenen Ordnern wird der archivierte `snapshot` in denselben
Ordner zurückgespielt und mit den vorhandenen ROM-/Save-Teilbäumen zusammengeführt.

Aktive Referenzen werden mit `qa_source` **vor** der ersten Bereinigung gesperrt;
`qa_copy` sperrt eine eigene eingefrorene Kopie **vor** dem Anlegen/Überschreiben.
`qa_profile` sperrt eine eigene QA-Spielidentity vor deren Installation.
`qa_cache` erfasst auch native Engine-Exporte. Kommandozeilen-Eingaben wie
`--zip`, `--engine-source`, `--reference-root` und `--cache-root` sowie explizite
QA-Referenz-Umgebungsvariablen werden zusätzlich vor der ersten Sammlung gepinnt.
Kindprozesse erben die Sperren über `qa_run`/`qa_popen`.

Ein lokaler LaunchAgent `com.maarten.origami-qa-cleanup` prüft zusätzlich alle
15 Minuten und bei Anmeldung. Dadurch werden auch liegen gebliebene Kopien
älterer Starter entdeckt. Unregistrierte Kopien erhalten mindestens eine Stunde
Schonzeit; dabei zählt auch die tatsächliche Erstellungs-/Änderungszeit, weil
`copy2` alte Dateizeiten übernimmt. Prozessargumente, offene Dateien, Arbeitsordner
und laufende LÖVE-Identities schützen ältere Leser zusätzlich. Bei fehlender
Prozessinspektion bleiben die Kopien erhalten. Laufende ältere Starter übernehmen
die neuen Prozess- und Platzwächter beim nächsten Start.

Der Agent verwendet eine unabhängig installierte, versionierte Kopie der vier
kleinen Python-Helfer unter `~/.local/lib/origami-qa-storage/`, ohne Netzwerkzugriff.
Er hängt nicht vom temporären Implementierungs-Worktree ab. Die kleine lokal
erstellte App `~/Applications/Origami QA Cleanup.app` trägt die gezielte
macOS-Dokumentenfreigabe; beim ersten Start kann macOS dafür einen Dialog zeigen.
Es wird kein Festplattenvollzugriff angefordert. Ein erfolgreicher echter
Hintergrundlauf muss alle registrierten Projektwurzeln lesen können; der Status
steht unter `~/.cache/origami-qa-storage/maintenance/status.json`. Das rotierende
Protokoll `~/.cache/origami-qa-storage/maintenance.log` ist mit einer Sicherung auf
insgesamt ungefähr 4 MiB begrenzt. Das Quell-/Modellarchiv ist dauerhaft;
einzigartige erhaltene Originaldaten zählen nicht zum löschbaren Cachebudget.

Installation/Aktualisierung für alle bestehenden Projektwurzeln (jeweils ein
`--root` angeben):

```sh
python3 tools/install_qa_maintenance.py --root /absoluter/projektordner
launchctl print gui/$(id -u)/com.maarten.origami-qa-cleanup
```

Deaktivieren:

```sh
launchctl bootout gui/$(id -u)/com.maarten.origami-qa-cleanup
```

Die individuelle Plist liegt unter
`~/Library/LaunchAgents/com.maarten.origami-qa-cleanup.plist`.
Die zeitgesteuerte Kontrolle startet keine Spiele oder Tests. Quell-Repositories
und Modelle werden nicht nach Alter gelöscht.

Zusätzliche Regressionen:

```sh
python3 tests/qa_legacy_storage_test.py
```
