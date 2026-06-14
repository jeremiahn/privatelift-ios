//
//  PrivateLiftWidgetBundle.swift
//  PrivateLiftWidget
//
//  Created by Jeremiah Nelson on 6/14/26.
//

import WidgetKit
import SwiftUI

@main
struct PrivateLiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrivateLiftWidget()
        PrivateLiftWidgetControl()
        PrivateLiftWidgetLiveActivity()
    }
}
