import Foundation
import CGSdxDefs

fileprivate func load<T>(_ dll: OpaquePointer, _ symbol: String) throws -> T {
	guard let ret = dlsym(UnsafeMutableRawPointer(dll), symbol) else {
		throw GSdx.LoadError.missingFunction(name: symbol)
	}
	return unsafeBitCast(ret, to: T.self)
}

public class GSdx {
	public enum LoadError: LocalizedError {
		case noDLL(path: String, msg: String)
		case missingFunction(name: String)
		case dllNotGSdx(type: Int)

		public var errorDescription: String? {
			switch self {
			case .noDLL(let path, let msg):
				return "Failed to load GSdx from \(path): \(msg)"
			case .missingFunction(let name):
				return "The GSdx DLL was missing the function \(name)"
			case .dllNotGSdx(let type):
				return "The GSdx DLL reported itself as the unexpected type \(type)"
			}
		}
	}

	typealias GifTransfer = @convention(c) (_ data: UnsafeRawPointer, _ size: CInt) -> Void

	let handle: OpaquePointer

	let gifTransfer: GifTransfer
	let gifTransfer1: GifTransfer
	let gifTransfer2: GifTransfer
	let gifTransfer3: GifTransfer
	public let vsync: @convention(c) (_ field: UInt8) -> Void
	public let reset: @convention(c) () -> Void
	let readFIFO2: @convention(c) (_ data: UnsafeMutableRawPointer, _ size: CInt) -> Void
	public let setGameCRC: @convention(c) (_ crc: CInt, _ options: CInt) -> Void
	let freeze: @convention(c) (_ mode: CInt, _ data: UnsafePointer<GSFreezeData>) -> CInt
	let open: @convention(c) (_ wnd: UnsafePointer<OpaquePointer?>, _ title: UnsafePointer<CChar>, _ renderer: CInt) -> CInt
	public let close: @convention(c) () -> Void
	public let shutdown: @convention(c) () -> Void
	public let configure: @convention(c) () -> Void
	public let setBaseMem: @convention(c) (_ data: UnsafeMutableRawPointer) -> Void
	public let setSettingsDir: @convention(c) (_ path: UnsafePointer<CChar>) -> Void
	let getLibName: @convention(c) () -> UnsafePointer<CChar>
	public let `init`: @convention(c) () -> ()
	public let makeSnapshot: @convention(c) (_ path: UnsafePointer<CChar>) -> CUnsignedInt

	public init(dll: String) throws {
		// Deinit doesn't run if the init fails, so we need separate cleanup
		var success = false

		guard let opened = dlopen(dll, RTLD_LAZY) else {
			throw LoadError.noDLL(path: dll, msg: String(cString: dlerror()))
		}
		defer { if !success { dlclose(opened) } }

		handle = OpaquePointer(opened)
		let getType: @convention(c) () -> UInt32 = try load(handle, "PS2EgetLibType")
		if getType() != 1 {
			throw LoadError.dllNotGSdx(type: Int(getType()))
		}
		gifTransfer  = try load(handle, "GSgifTransfer")
		gifTransfer1 = try load(handle, "GSgifTransfer1")
		gifTransfer2 = try load(handle, "GSgifTransfer2")
		gifTransfer3 = try load(handle, "GSgifTransfer3")
		vsync        = try load(handle, "GSvsync")
		reset        = try load(handle, "GSreset")
		readFIFO2    = try load(handle, "GSreadFIFO2")
		setGameCRC   = try load(handle, "GSsetGameCRC")
		freeze       = try load(handle, "GSfreeze")
		open         = try load(handle, "GSopen")
		close        = try load(handle, "GSclose")
		shutdown     = try load(handle, "GSshutdown")
		configure    = try load(handle, "GSconfigure")
		setBaseMem   = try load(handle, "GSsetBaseMem")
		setSettingsDir = try load(handle, "GSsetSettingsDir")
		getLibName   = try load(handle, "PS2EgetLibName")
		`init`       = try load(handle, "GSinit")
		makeSnapshot = try load(handle, "GSmakeSnapshot")

		success = true
	}

	deinit {
		dlclose(UnsafeMutableRawPointer(handle))
	}
}

extension GSdx {
	public enum Renderer: Int8 {
		case undefined = -1
		case dx1011_hw = 3
		case dx1011_sw
		case null = 11
		case ogl_hw
		case ogl_sw
		case dx1011_opencl = 15
		case ogl_opencl = 17
	}
}

extension GSdx {
	// MARK: Make open easier to use
	public struct OpenFailedError: Error {}

	func open(wnd: UnsafePointer<OpaquePointer?>, title: UnsafePointer<CChar>) throws {
		if open(wnd, title, 0) < 0 {
			throw OpenFailedError()
		}
	}
}

extension GSdx {
	public enum FreezeMode: Int8 {
		case load = 0
		case save = 1
		case size = 2
	}

	public struct DumpTooOld: Error {}

	func freeze(mode: FreezeMode, data: UnsafePointer<GSFreezeData>) throws {
		if freeze(CInt(mode.rawValue), data) < 0 {
			throw DumpTooOld()
		}
	}
}

extension GSdx {
	// MARK: Other convenience functions

	public func gifTransfer(_ data: UnsafeRawBufferPointer, path: GSData.TransferPath) {
		let ptr = data.baseAddress!
		let len = CInt(data.count / 16)
		switch path {
		case .path1Old:
			let addr = 0x4000 - data.count
			gifTransfer1(ptr - addr, CInt(addr))
		case .path2: gifTransfer2(ptr, len)
		case .path3: gifTransfer3(ptr, len)
		case .path1New: gifTransfer(ptr, len)
		}
	}

	public func readFIFO2(into data: UnsafeMutableRawBufferPointer) {
		readFIFO2(data.baseAddress!, CInt(data.count))
	}

	public var name: String { String(cString: getLibName()) }
}
