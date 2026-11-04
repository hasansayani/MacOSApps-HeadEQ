// Platform-neutral libm import so EQCore builds without Foundation.
#if canImport(Darwin)
@_exported import Darwin
#elseif canImport(Glibc)
@_exported import Glibc
#elseif canImport(Musl)
@_exported import Musl
#elseif canImport(Android)
@_exported import Android
#elseif canImport(ucrt)
@_exported import ucrt
#endif
