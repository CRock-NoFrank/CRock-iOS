//
//  CRockWidgetBundle.swift
//  CRockWidget
//
//  Created by 나현흠 on 8/9/25.
//

import WidgetKit
import SwiftUI

@main
struct CRockWidgetBundle: WidgetBundle {
    var body: some Widget {
        CRockWidget()
//        CRockWidgetControl()
        CRockWidgetLiveActivity()
    }
}
