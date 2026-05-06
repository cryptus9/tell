//
//  Item.swift
//  tell
//
//  Created by Jannes Münse on 06.05.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
