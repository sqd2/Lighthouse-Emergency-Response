# Lines of Code Analysis

This document provides a comprehensive analysis of the codebase size for the Lighthouse project.

## Summary

**Total Lines of Code: 28,213**

This count includes all source code files but excludes:
- Build artifacts and directories (build/, .dart_tool/, node_modules/)
- Lock files
- Binary files (images, fonts, etc.)
- Git repository files

## Detailed Breakdown by Language

| Language | Files | Blank Lines | Comments | Code Lines |
|----------|-------|-------------|----------|------------|
| Dart | 60 | 1,873 | 1,052 | 16,782 |
| Markdown | 15 | 1,794 | 0 | 7,027 |
| JavaScript | 14 | 295 | 474 | 1,337 |
| XML | 21 | 10 | 41 | 847 |
| C++ | 8 | 124 | 70 | 501 |
| JSON | 10 | 0 | 0 | 485 |
| HTML | 1 | 81 | 23 | 460 |
| CMake | 8 | 84 | 113 | 365 |
| C/C++ Header | 8 | 51 | 65 | 103 |
| Swift | 6 | 15 | 7 | 87 |
| Gradle | 3 | 13 | 10 | 77 |
| Windows Resource | 1 | 23 | 29 | 69 |
| YAML | 2 | 16 | 87 | 51 |
| DOS Batch | 1 | 0 | 0 | 10 |
| Properties | 2 | 0 | 0 | 9 |
| Kotlin | 1 | 2 | 0 | 3 |
| **TOTAL** | **161** | **4,381** | **1,971** | **28,213** |

## Breakdown by Component

### Main Application Code (lib/)
- **Files:** 56
- **Code Lines:** 16,145
- **Language:** Dart
- **Description:** Core Flutter application code including screens, widgets, services, models, and utilities

### Firebase Cloud Functions (functions/)
- **Files:** 13
- **Code Lines:** 1,070
- **Languages:** JavaScript (1,040 lines), JSON (30 lines)
- **Description:** Backend serverless functions for notifications, emergency triggers, and API endpoints

### Tests (test/)
- **Files:** 4
- **Code Lines:** 637
- **Language:** Dart
- **Description:** Unit tests for models and utilities

### Platform-Specific Code
- **Android:** Gradle, XML, Kotlin configuration files
- **iOS:** Swift, XML (Xcode) configuration files
- **macOS:** Swift, XML (Xcode) configuration files
- **Linux:** C++, CMake build files
- **Windows:** C++, CMake build files

### Documentation
- **Files:** 15 Markdown files
- **Lines:** 7,027
- **Description:** Comprehensive documentation including architecture, setup guides, session summaries, and feature documentation

## Key Statistics

- **Primary Language:** Dart (59.5% of code)
- **Code-to-Comment Ratio:** 14.3:1
- **Test Coverage:** 637 test lines for 16,145 application lines (~3.9% test ratio)
- **Documentation:** 7,027 lines of markdown documentation

## How to Update This Report

To regenerate these statistics, run the following command from the project root:

```bash
cloc . --fullpath --not-match-d='(\.git|build|node_modules|\.dart_tool)' --exclude-ext=lock,svg,png,jpg,jpeg,gif,ico,ttf,woff,woff2
```

For detailed breakdown by directory:

```bash
# Main source code
cloc lib

# Firebase functions
cloc functions

# Tests
cloc test
```

## Tool Used

These statistics were generated using [cloc](https://github.com/AlDanial/cloc) (Count Lines of Code) v1.98.

---
*Last Updated: December 31, 2025*
