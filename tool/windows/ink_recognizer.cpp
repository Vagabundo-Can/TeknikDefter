// Windows el yazısı tanıma: Windows.UI.Input.Inking.InkRecognizerContainer (C++/WinRT).
// Tanıma arka plan iş parçacığında yapılır; sonuç pencere mesajıyla platform iş parçacığına döner.

#include "ink_recognizer.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <thread>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Input.Inking.h>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

HWND g_hwnd = nullptr;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;

struct InkJob {
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
  std::vector<std::string> candidates;
  std::string error;
};

std::string ToUtf8(const winrt::hstring& s) { return winrt::to_string(s); }

bool Contains(const std::wstring& hay, const wchar_t* needle) { return hay.find(needle) != std::wstring::npos; }

// lang: "tr" → Türkçe tanıyıcı varsa onu seç
void PickRecognizer(winrt::Windows::UI::Input::Inking::InkRecognizerContainer& rec, const std::string& lang) {
  auto list = rec.GetRecognizers();
  for (auto const& r : list) {
    std::wstring name(r.Name().c_str());
    if (lang == "tr" && (Contains(name, L"Türk") || Contains(name, L"Turkish"))) {
      rec.SetDefaultRecognizer(r);
      return;
    }
  }
}

void Recognize(InkJob* job, std::vector<std::vector<double>> strokes, std::string lang) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    using namespace winrt::Windows::UI::Input::Inking;
    using winrt::Windows::Foundation::Point;
    InkStrokeBuilder builder;
    InkStrokeContainer container;
    for (auto const& s : strokes) {
      if (s.size() < 4) continue;
      std::vector<Point> pts;
      for (size_t i = 0; i + 1 < s.size(); i += 2) {
        pts.push_back(Point(static_cast<float>(s[i] * 10.0), static_cast<float>(s[i + 1] * 10.0)));
      }
      auto stroke = builder.CreateStroke(winrt::single_threaded_vector<Point>(std::move(pts)));
      container.AddStroke(stroke);
    }
    InkRecognizerContainer rec;
    if (rec.GetRecognizers().Size() == 0) {
      job->error = "Bu Windows'ta el yazısı tanıyıcı yok (Ayarlar > Zaman ve dil > Dil > Türkçe > El yazısı).";
    } else {
      PickRecognizer(rec, lang);
      auto results = rec.RecognizeAsync(container, InkRecognitionTarget::All).get();
      for (int alt = 0; alt < 3; ++alt) {
        std::string line;
        bool any = false;
        for (auto const& r : results) {
          auto c = r.GetTextCandidates();
          if (c.Size() == 0) continue;
          uint32_t idx = alt < static_cast<int>(c.Size()) ? static_cast<uint32_t>(alt) : 0;
          if (!line.empty()) line += " ";
          line += ToUtf8(c.GetAt(idx));
          any = true;
        }
        if (any && (job->candidates.empty() || job->candidates.back() != line)) job->candidates.push_back(line);
      }
    }
  } catch (winrt::hresult_error const& e) {
    job->error = ToUtf8(e.message());
  } catch (...) {
    job->error = "El yazısı tanınamadı";
  }
  PostMessage(g_hwnd, WM_TD_INK, 0, reinterpret_cast<LPARAM>(job));
}

}  // namespace

void InkOnPosted(LPARAM lparam) {
  auto* job = reinterpret_cast<InkJob*>(lparam);
  if (!job->error.empty()) {
    job->result->Error("ink", job->error);
  } else {
    EncodableList out;
    for (auto const& c : job->candidates) out.push_back(EncodableValue(c));
    job->result->Success(EncodableValue(out));
  }
  delete job;
}

void RegisterInkChannel(flutter::FlutterEngine* engine, HWND hwnd) {
  g_hwnd = hwnd;
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(engine->messenger(), "teknik_defter/ink",
                                                                        &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler([](const flutter::MethodCall<EncodableValue>& call,
                                     std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    std::string lang = "tr";
    if (args) {
      auto it = args->find(EncodableValue("lang"));
      if (it != args->end() && std::holds_alternative<std::string>(it->second)) lang = std::get<std::string>(it->second);
    }
    if (call.method_name() == "isReady") {
      result->Success(EncodableValue(true));
      return;
    }
    if (call.method_name() != "recognize") {
      result->NotImplemented();
      return;
    }
    std::vector<std::vector<double>> strokes;
    if (args) {
      auto it = args->find(EncodableValue("strokes"));
      if (it != args->end()) {
        if (const auto* list = std::get_if<EncodableList>(&it->second)) {
          for (auto const& s : *list) {
            std::vector<double> pts;
            if (const auto* sl = std::get_if<EncodableList>(&s)) {
              for (auto const& v : *sl) {
                if (const auto* d = std::get_if<double>(&v)) pts.push_back(*d);
                else if (const auto* i = std::get_if<int32_t>(&v)) pts.push_back(static_cast<double>(*i));
              }
            } else if (const auto* dl = std::get_if<std::vector<double>>(&s)) {
              pts = *dl;
            }
            strokes.push_back(std::move(pts));
          }
        }
      }
    }
    auto* job = new InkJob{std::move(result), {}, {}};
    std::thread(Recognize, job, std::move(strokes), lang).detach();
  });
}
