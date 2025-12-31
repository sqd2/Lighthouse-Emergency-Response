#!/bin/bash

# Lines of Code Counter Script for Lighthouse Project
# This script provides a comprehensive analysis of the codebase size

echo "=================================="
echo "   Lighthouse Project LOC Report"
echo "=================================="
echo ""

# Check if cloc is installed
if ! command -v cloc &> /dev/null; then
    echo "Error: cloc is not installed."
    echo "Please install it using: sudo apt-get install cloc"
    echo "Or visit: https://github.com/AlDanial/cloc"
    exit 1
fi

echo "=== TOTAL PROJECT SUMMARY ==="
echo ""
cloc . --fullpath --not-match-d='(\.git|build|node_modules|\.dart_tool)' \
    --exclude-ext=lock,svg,png,jpg,jpeg,gif,ico,ttf,woff,woff2

echo ""
echo "=== BREAKDOWN BY MAIN DIRECTORIES ==="
echo ""

echo "--- Dart Source Code (lib/) ---"
cloc lib
echo ""

echo "--- Firebase Functions (functions/) ---"
cloc functions
echo ""

echo "--- Tests (test/) ---"
cloc test
echo ""

echo "=================================="
echo "Report generation complete!"
echo "=================================="
