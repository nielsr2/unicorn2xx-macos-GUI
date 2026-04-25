/*
 * UnicornDevice.swift
 * UnicornEEG
 *
 * Manages the serial-over-Bluetooth connection to the Unicorn Hybrid Black device.
 * Wraps libserialport for port enumeration, connection, and packet reading.
 */

import Foundation

struct SerialPortInfo {
    let index: Int
    let name: String
    let description: String
    let isUnicorn: Bool
}

enum UnicornDeviceError: LocalizedError {
    case noPortsFound
    case cannotOpenPort(String)
    case cannotConfigure(String)
    case cannotStartAcquisition
    case incorrectResponse
    case readFailed
    case portNotOpen

    var errorDescription: String? {
        switch self {
        case .noPortsFound: return "No serial ports found."
        case .cannotOpenPort(let msg): return "Cannot open port: \(msg)"
        case .cannotConfigure(let msg): return "Cannot configure port: \(msg)"
        case .cannotStartAcquisition: return "Cannot start data stream."
        case .incorrectResponse: return "Incorrect response from device."
        case .readFailed: return "Cannot read packet."
        case .portNotOpen: return "Port is not open."
        }
    }
}

class UnicornDevice {
    private var port: OpaquePointer?
    private let timeout: UInt32 = 5000

    private let startAcq: [UInt8] = [0x61, 0x7C, 0x87]
    private let stopAcq: [UInt8] = [0x63, 0x5C, 0xC5]

    var isConnected: Bool { port != nil }

    // MARK: - Port Enumeration

    static func listPorts() -> [SerialPortInfo] {
        var portList: UnsafeMutablePointer<OpaquePointer?>?
        let result = sp_list_ports(&portList)
        guard result == SP_OK, let list = portList else { return [] }

        var ports: [SerialPortInfo] = []
        var i = 0
        while let p = list[i] {
            let name = String(cString: sp_get_port_name(p))
            let rawDesc = sp_get_port_description(p)
            let desc = rawDesc != nil ? String(cString: rawDesc!) : ""
            let isUnicorn = name.contains("UN") || desc.contains("UN")
            ports.append(SerialPortInfo(index: i, name: name, description: desc, isUnicorn: isUnicorn))
            i += 1
        }

        sp_free_port_list(list)
        return ports
    }

    // MARK: - Connection

    func connect(portName: String) throws {
        var p: OpaquePointer?
        guard sp_get_port_by_name(portName, &p) == SP_OK, let newPort = p else {
            throw UnicornDeviceError.cannotOpenPort(portName)
        }

        guard sp_open(newPort, SP_MODE_READ_WRITE) == SP_OK else {
            sp_free_port(newPort)
            throw UnicornDeviceError.cannotOpenPort(portName)
        }

        // Configure: 115200, 8N1, no flow control
        guard sp_set_baudrate(newPort, 115200) == SP_OK,
              sp_set_bits(newPort, 8) == SP_OK,
              sp_set_parity(newPort, SP_PARITY_NONE) == SP_OK,
              sp_set_stopbits(newPort, 1) == SP_OK,
              sp_set_flowcontrol(newPort, SP_FLOWCONTROL_NONE) == SP_OK else {
            sp_close(newPort)
            sp_free_port(newPort)
            throw UnicornDeviceError.cannotConfigure("Failed to set port parameters")
        }

        self.port = newPort
    }

    func disconnect() {
        if let p = port {
            sp_close(p)
            sp_free_port(p)
            port = nil
        }
    }

    // MARK: - Acquisition Control

    func startAcquisition() throws {
        guard let p = port else { throw UnicornDeviceError.portNotOpen }

        let written = startAcq.withUnsafeBufferPointer { buf in
            sp_blocking_write(p, buf.baseAddress, buf.count, timeout)
        }
        guard written.rawValue == 3 else {
            throw UnicornDeviceError.cannotStartAcquisition
        }

        var response = [UInt8](repeating: 0, count: 3)
        let read = response.withUnsafeMutableBufferPointer { buf in
            sp_blocking_read(p, buf.baseAddress, buf.count, timeout)
        }
        guard read.rawValue == 3, response[0] == 0x00, response[1] == 0x00, response[2] == 0x00 else {
            throw UnicornDeviceError.incorrectResponse
        }
    }

    func stopAcquisition() {
        guard let p = port else { return }
        stopAcq.withUnsafeBufferPointer { buf in
            _ = sp_blocking_write(p, buf.baseAddress, buf.count, timeout)
        }
    }

    // MARK: - Packet Reading

    func readPacket() -> UnicornSample? {
        guard let p = port else { return nil }

        var buf = [UInt8](repeating: 0, count: PacketParser.packetSize)
        let result = buf.withUnsafeMutableBufferPointer { bufPtr in
            sp_blocking_read(p, bufPtr.baseAddress, bufPtr.count, timeout)
        }
        guard result.rawValue == PacketParser.packetSize else { return nil }

        return buf.withUnsafeBufferPointer { bufPtr in
            PacketParser.parse(bufPtr.baseAddress!)
        }
    }

    deinit {
        disconnect()
    }
}
