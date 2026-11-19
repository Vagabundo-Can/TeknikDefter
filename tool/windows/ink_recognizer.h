#pragma once
#include <flutter/flutter_engine.h>
#include <windows.h>

// Windows el yazısı tanıma (Windows.UI.Input.Inking). Kanal: teknik_defter/ink
#define WM_TD_INK (WM_APP + 77)
void RegisterInkChannel(flutter::FlutterEngine* engine, HWND hwnd);
void InkOnPosted(LPARAM lparam);
