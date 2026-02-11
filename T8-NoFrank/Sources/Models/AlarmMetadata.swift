//
//  AlarmMetadata.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 2/10/26.
//

#if canImport(AlarmKit)
import AlarmKit

@available(iOS 26.0, *)
struct AlarmMetadata: AlarmKit.AlarmMetadata, Codable {
    init() {}
}
#endif
