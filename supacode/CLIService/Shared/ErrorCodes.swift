// ProwlShared/ErrorCodes.swift
// Stable error codes matching schema.md contracts.

import Foundation

public enum CLIErrorCode {
  // Common
  public static let appNotRunning = "APP_NOT_RUNNING"
  public static let invalidArgument = "INVALID_ARGUMENT"
  public static let targetNotFound = "TARGET_NOT_FOUND"
  public static let targetNotUnique = "TARGET_NOT_UNIQUE"

  // Open
  public static let pathNotFound = "PATH_NOT_FOUND"
  public static let pathNotDirectory = "PATH_NOT_DIRECTORY"
  public static let pathNotAllowed = "PATH_NOT_ALLOWED"
  public static let launchFailed = "LAUNCH_FAILED"
  public static let openFailed = "OPEN_FAILED"

  // List
  public static let listFailed = "LIST_FAILED"

  // Focus
  public static let focusFailed = "FOCUS_FAILED"

  // Send
  public static let emptyInput = "EMPTY_INPUT"
  public static let sendFailed = "SEND_FAILED"

  // Key
  public static let invalidRepeat = "INVALID_REPEAT"
  public static let noActivePane = "NO_ACTIVE_PANE"
  public static let unsupportedKey = "UNSUPPORTED_KEY"
  public static let keyDeliveryFailed = "KEY_DELIVERY_FAILED"

  // Read
  public static let readFailed = "READ_FAILED"

  // Transport
  public static let transportFailed = "TRANSPORT_FAILED"
  public static let timeout = "TIMEOUT"
}
