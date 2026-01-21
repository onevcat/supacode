//
//  Github.swift
//  supacode
//
//  Created by khoi on 20/1/26.
//

import Foundation

enum Github {
  static func profilePictureURL(username: String, size: Int = 200) -> URL? {
    URL(string: "https://github.com/\(username).png?size=\(size)")
  }
}
