// ChatConfig.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Backend-URL + Anon-Key +
// Timeouts für die Edge-Function-Calls. Single-Source-of-Truth für
// alle Chat-bezogenen Network-Konstanten.
//
// Der Anon-Key ist per Supabase-Konvention publishable-safe (er
// identifiziert nur das Projekt, gewährt ohne RLS-Policy KEINE
// Schreibrechte und ist im iOS-Bundle als Bare-String akzeptabel).
// Das eigentliche Sensitive Material (Anthropic-API-Key) lebt
// serverseitig in Supabase Secrets — der iOS-Client kann nur via
// Edge Function dorthin proxen.

import Foundation

enum ChatConfig {
    /// Edge-Function-Endpoint des Léa-Chat-Proxy.
    static let backendURL = URL(
        string: "https://lvqayhkdgdypdvzdinvy.supabase.co/functions/v1/chat"
    )!

    /// Supabase Anon-Key (publishable-safe, kein Geheimnis).
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx2cWF5aGtkZ2R5cGR2emRpbnZ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgzMTg5OTEsImV4cCI6MjA5Mzg5NDk5MX0.-RG6nv5X5V6tMl5MCBljYtyu_z9W9atpummftlEZPM8"

    /// Request-Timeout in Sekunden — Streams können länger dauern,
    /// 30 s ist ein vernünftiger Compromise zwischen User-Geduld und
    /// Network-Hangs.
    static let timeoutSeconds: TimeInterval = 30
}
