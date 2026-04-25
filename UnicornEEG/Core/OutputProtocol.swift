/*
 * OutputProtocol.swift
 * UnicornEEG
 *
 * Protocol for output sinks that receive EEG samples from the StreamEngine.
 */

import Foundation

protocol OutputSink: AnyObject {
    var name: String { get }
    func start() throws
    func processSample(_ sample: UnicornSample)
    func stop()
}
