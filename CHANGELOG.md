# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2024-02-27

### Added

- Added `auto_flush` option to the OpenAI integration to automatically flush after each API call
- Added comprehensive tests for the `auto_flush` functionality

### Changed

- Removed mutex locks in favor of using Ruby's thread-safe Queue class directly
- Simplified the queue operations for better thread safety
- Improved background timer implementation

### Fixed

- Fixed potential deadlocks in multi-threaded environments like Sidekiq
- Fixed race conditions in the flush mechanism

## [0.1.0] - 2024-02-24

### Added

- Initial release of the Langfuse Ruby client
- Core functionality for creating traces, generations, spans, and events
- OpenAI integration for automatic tracing of API calls
- Thread-local client support for multi-threaded environments
- Batch processing with automatic flushing
- Comprehensive test suite
