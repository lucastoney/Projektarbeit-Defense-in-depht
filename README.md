# Technischer Teil der Projektarbeit: Defense in Depth

Dieses Repository enthält die technische Umsetzung der Cyber-Security-Projektarbeit zur automatisierten Absicherung und Überwachung eines Linux-Servers nach dem Defense-in-Depth-Prinzip in einer isolierten Laborumgebung.

## Technischer Aufbau

- `Vagrantfile`: Definition der Server- und Tester-VM
- `config/`: Konfiguration von nftables, SSH, Fail2ban, Auditd, AIDE und rsyslog
- `scripts/`: Bereitstellung, Konfiguration und technische Prüfungen
- `tests/`: Automatisierte End-to-End-Tests

## Voraussetzungen

- Vagrant
- VirtualBox
- PowerShell
- lokale Umgebungsvariable `LAB_PASSWORD` ohne Speicherung des Passworts im Repository

Dieses Repository enthält ausschliesslich die technische Umsetzung.

Die schriftliche Projektdokumentation sowie Screenshots und Nachweise werden separat eingereicht.
