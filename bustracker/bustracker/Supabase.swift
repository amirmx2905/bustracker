//
//  Supabase.swift
//  bustracker
//
//  Created by Amir Sebastián Flores Cardona on 28/04/26.
//

import Foundation
import Supabase

private struct SupabaseConfig {
  let url: URL
  let key: String

  static func load() -> SupabaseConfig {
    let processEnv = ProcessInfo.processInfo.environment
    let fileEnv = DotEnv.loadFromBundle()

    let urlString = processEnv["SUPABASE_URL"]
      ?? fileEnv["SUPABASE_URL"]
    let key = processEnv["SUPABASE_KEY"]
      ?? fileEnv["SUPABASE_KEY"]

    guard
      let urlString,
      let url = URL(string: urlString),
      let key,
      !key.isEmpty
    else {
      fatalError(
        "Missing Supabase config. Set SUPABASE_URL and SUPABASE_KEY in scheme env vars or in a bundled .env file."
      )
    }

    return SupabaseConfig(url: url, key: key)
  }
}

private enum DotEnv {
  static func loadFromBundle() -> [String: String] {
    guard let url = bundleEnvURL,
          let raw = try? String(contentsOf: url, encoding: .utf8) else {
      return [:]
    }

    var values: [String: String] = [:]

    for line in raw.split(whereSeparator: \Character.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty || trimmed.hasPrefix("#") {
        continue
      }

      let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { continue }

      let key = parts[0].trimmingCharacters(in: .whitespaces)
      let value = parts[1]
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

      if !key.isEmpty {
        values[key] = value
      }
    }

    return values
  }

  private static var bundleEnvURL: URL? {
    if let hidden = Bundle.main.url(forResource: ".env", withExtension: nil) {
      return hidden
    }

    return Bundle.main.url(forResource: "env", withExtension: nil)
  }
}

private let supabaseConfig = SupabaseConfig.load()

let supabase = SupabaseClient(
  supabaseURL: supabaseConfig.url,
  supabaseKey: supabaseConfig.key
)
