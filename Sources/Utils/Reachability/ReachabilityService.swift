//
//  ReachabilityService.swift
//  RxExample
//
//  Created by Vodovozov Gleb on 10/22/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift

#if swift(>=3.2)
    import class Dispatch.DispatchQueue
#else
    import class Dispatch.queue.DispatchQueue
#endif

public enum ReachabilityStatus {
    case reachable(viaWiFi: Bool)
    case unreachable
}

extension ReachabilityStatus {
    var reachable: Bool {
        switch self {
        case .reachable:
            return true
        case .unreachable:
            return false
        }
    }
}

protocol ReachabilityService {
    var reachability: Observable<ReachabilityStatus> { get }
}

enum ReachabilityServiceError: Error {
    case failedToCreate
}

class DefaultReachabilityService
    : ReachabilityService {
    private let _reachabilitySubject: BehaviorSubject<ReachabilityStatus>

    var reachability: Observable<ReachabilityStatus> {
        return _reachabilitySubject.asObservable()
    }

    let _reachability: Reachability

    init() throws {
        guard let reachabilityRef = Reachability() else { throw ReachabilityServiceError.failedToCreate }
        let reachabilitySubject = BehaviorSubject<ReachabilityStatus>(value: .unreachable)

        // so main thread isn't blocked when reachability via WiFi is checked
        let backgroundQueue = DispatchQueue(label: "reachability.wificheck")

        reachabilityRef.whenReachable = { reachability in
            backgroundQueue.async {
                reachabilitySubject.on(.next(.reachable(viaWiFi: reachabilityRef.isReachableViaWiFi)))
            }
        }

        reachabilityRef.whenUnreachable = { reachability in
            backgroundQueue.async {
                reachabilitySubject.on(.next(.unreachable))
            }
        }

        try reachabilityRef.startNotifier()
        _reachability = reachabilityRef
        _reachabilitySubject = reachabilitySubject
    }

    deinit {
        _reachability.stopNotifier()
    }
}

extension ObservableConvertibleType {
    func retryOnBecomesReachable(_ reachabilityService: ReachabilityService) -> Observable<Element> {
        return self.asObservable()
            .catchError { (e) -> Observable<Element> in
                reachabilityService.reachability
                    .skip(1)
                    .filter { $0.reachable }
                    .take(1)
                    .flatMap { _ in
                        Observable.error(e)
                    }
            }
            .retry()
    }
}
