#include "screen_capture.h"

#include <d3d11.h>
#include <dxgi.h>
#include <shellscalingapi.h>
#include <wincodec.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

namespace wgc = winrt::Windows::Graphics::Capture;
namespace wdx = winrt::Windows::Graphics::DirectX;
namespace wgi = winrt::Windows::Graphics::Imaging;
namespace ocr = winrt::Windows::Media::Ocr;

struct Pixels {
  std::vector<unsigned char> bgra;  // top-down, 4 bytes per pixel
  int width = 0;
  int height = 0;
};

// ───────────────────────── Windows.Graphics.Capture ─────────────────────────

bool CaptureWgc(HMONITOR monitor, Pixels* out) {
  try {
    if (!wgc::GraphicsCaptureSession::IsSupported()) return false;

    winrt::com_ptr<ID3D11Device> d3d;
    winrt::com_ptr<ID3D11DeviceContext> context;
    winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                                           D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                                           D3D11_SDK_VERSION, d3d.put(), nullptr, context.put()));
    auto dxgi = d3d.as<IDXGIDevice>();
    winrt::com_ptr<::IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
    auto device = inspectable.as<wdx::Direct3D11::IDirect3DDevice>();

    auto interop = winrt::get_activation_factory<wgc::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    wgc::GraphicsCaptureItem item{nullptr};
    winrt::check_hresult(interop->CreateForMonitor(monitor, winrt::guid_of<wgc::GraphicsCaptureItem>(),
                                                   winrt::put_abi(item)));

    auto pool = wgc::Direct3D11CaptureFramePool::CreateFreeThreaded(
        device, wdx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 1, item.Size());
    auto session = pool.CreateCaptureSession(item);
    try {
      session.IsCursorCaptureEnabled(false);  // Windows 10 2004+
    } catch (...) {
    }
    try {
      session.IsBorderRequired(false);  // Windows 11; needs a capability, else the yellow border shows
    } catch (...) {
    }

    HANDLE arrived = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    auto token = pool.FrameArrived([arrived](auto&&, auto&&) { SetEvent(arrived); });
    session.StartCapture();
    const DWORD wait = WaitForSingleObject(arrived, 1500);
    wgc::Direct3D11CaptureFrame frame{nullptr};
    if (wait == WAIT_OBJECT_0) frame = pool.TryGetNextFrame();
    pool.FrameArrived(token);
    CloseHandle(arrived);
    if (!frame) {
      session.Close();
      pool.Close();
      return false;
    }

    auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<ID3D11Texture2D> texture;
    winrt::check_hresult(access->GetInterface(winrt::guid_of<ID3D11Texture2D>(), texture.put_void()));

    D3D11_TEXTURE2D_DESC desc{};
    texture->GetDesc(&desc);
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;
    winrt::com_ptr<ID3D11Texture2D> staging;
    winrt::check_hresult(d3d->CreateTexture2D(&desc, nullptr, staging.put()));
    context->CopyResource(staging.get(), texture.get());

    D3D11_MAPPED_SUBRESOURCE mapped{};
    winrt::check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
    out->width = static_cast<int>(desc.Width);
    out->height = static_cast<int>(desc.Height);
    out->bgra.resize(static_cast<size_t>(out->width) * out->height * 4);
    for (int y = 0; y < out->height; ++y) {
      std::memcpy(&out->bgra[static_cast<size_t>(y) * out->width * 4],
                  static_cast<unsigned char*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch,
                  static_cast<size_t>(out->width) * 4);
    }
    context->Unmap(staging.get(), 0);
    frame.Close();
    session.Close();
    pool.Close();
    return true;
  } catch (...) {
    return false;
  }
}

// ───────────────────────── GDI fallback ─────────────────────────

bool CaptureGdi(const RECT& rect, Pixels* out) {
  const int w = rect.right - rect.left;
  const int h = rect.bottom - rect.top;
  HDC screen = GetDC(nullptr);
  HDC mem = CreateCompatibleDC(screen);
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;  // top-down
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  bool ok = false;
  if (dib != nullptr) {
    HGDIOBJ old = SelectObject(mem, dib);
    ok = BitBlt(mem, 0, 0, w, h, screen, rect.left, rect.top, SRCCOPY | CAPTUREBLT) != FALSE;
    if (ok) {
      out->width = w;
      out->height = h;
      out->bgra.assign(static_cast<unsigned char*>(bits), static_cast<unsigned char*>(bits) + static_cast<size_t>(w) * h * 4);
      for (size_t i = 3; i < out->bgra.size(); i += 4) out->bgra[i] = 255;
    }
    SelectObject(mem, old);
    DeleteObject(dib);
  }
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  return ok;
}

// ───────────────────────── Scale + JPEG (WIC) ─────────────────────────

bool EncodeJpeg(const Pixels& px, int max_side, int quality, SottoCapture* out) {
  winrt::com_ptr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.put())))) {
    return false;
  }
  winrt::com_ptr<IWICBitmap> bitmap;
  if (FAILED(factory->CreateBitmapFromMemory(px.width, px.height, GUID_WICPixelFormat32bppBGRA, px.width * 4,
                                             static_cast<UINT>(px.bgra.size()),
                                             const_cast<BYTE*>(px.bgra.data()), bitmap.put()))) {
    return false;
  }
  const int longest = px.width > px.height ? px.width : px.height;
  const double k = longest > max_side ? static_cast<double>(max_side) / longest : 1.0;
  const UINT w = static_cast<UINT>(px.width * k + 0.5);
  const UINT h = static_cast<UINT>(px.height * k + 0.5);

  winrt::com_ptr<IWICBitmapScaler> scaler;
  factory->CreateBitmapScaler(scaler.put());
  if (FAILED(scaler->Initialize(bitmap.get(), w, h, WICBitmapInterpolationModeHighQualityCubic))) return false;
  winrt::com_ptr<IWICFormatConverter> converter;
  factory->CreateFormatConverter(converter.put());
  if (FAILED(converter->Initialize(scaler.get(), GUID_WICPixelFormat24bppBGR, WICBitmapDitherTypeNone, nullptr, 0,
                                   WICBitmapPaletteTypeCustom))) {
    return false;
  }

  winrt::com_ptr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, stream.put()))) return false;
  winrt::com_ptr<IWICBitmapEncoder> encoder;
  factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, encoder.put());
  encoder->Initialize(stream.get(), WICBitmapEncoderNoCache);
  winrt::com_ptr<IWICBitmapFrameEncode> frame;
  winrt::com_ptr<IPropertyBag2> props;
  encoder->CreateNewFrame(frame.put(), props.put());
  PROPBAG2 option{};
  wchar_t name[] = L"ImageQuality";
  option.pstrName = name;
  VARIANT value;
  VariantInit(&value);
  value.vt = VT_R4;
  value.fltVal = static_cast<float>(quality) / 100.0f;
  props->Write(1, &option, &value);
  frame->Initialize(props.get());
  frame->SetSize(w, h);
  WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
  frame->SetPixelFormat(&format);
  if (FAILED(frame->WriteSource(converter.get(), nullptr)) || FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return false;
  }

  HGLOBAL global = nullptr;
  GetHGlobalFromStream(stream.get(), &global);
  STATSTG stat{};
  stream->Stat(&stat, STATFLAG_NONAME);
  const size_t size = static_cast<size_t>(stat.cbSize.QuadPart);
  out->jpeg = static_cast<unsigned char*>(std::malloc(size));
  if (out->jpeg == nullptr) return false;
  void* data = GlobalLock(global);
  std::memcpy(out->jpeg, data, size);
  GlobalUnlock(global);
  out->jpeg_size = size;
  out->width = static_cast<int>(w);
  out->height = static_cast<int>(h);
  return true;
}

// ───────────────────────── Text (Windows.Media.Ocr) ─────────────────────────

void JsonText(std::string& out, const std::string& s) {
  out.push_back('"');
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') {
      out.push_back('\\');
      out.push_back(static_cast<char>(c));
    } else if (c < 0x20) {
      char buf[8];
      std::snprintf(buf, sizeof(buf), "\\u%04x", c);
      out += buf;
    } else {
      out.push_back(static_cast<char>(c));
    }
  }
  out.push_back('"');
}

std::string Utf8(const winrt::hstring& s) { return winrt::to_string(s); }

// The text on [px], line by line, boxes multiplied by [k] (the encoded
// image's scale). The OCR engine takes at most MaxImageDimension a side: a
// bigger capture is read at that size and the boxes scaled back.
char* Recognize(const Pixels& px, double k) {
  try {
    ocr::OcrEngine engine = ocr::OcrEngine::TryCreateFromUserProfileLanguages();
    if (!engine) return nullptr;
    const int limit = static_cast<int>(ocr::OcrEngine::MaxImageDimension());
    const int longest = px.width > px.height ? px.width : px.height;
    const int step = longest > limit ? (longest + limit - 1) / limit : 1;
    const int w = px.width / step;
    const int h = px.height / step;
    wgi::SoftwareBitmap bitmap(wgi::BitmapPixelFormat::Bgra8, w, h, wgi::BitmapAlphaMode::Premultiplied);
    winrt::Windows::Storage::Streams::Buffer buffer(static_cast<uint32_t>(w * h * 4));
    buffer.Length(buffer.Capacity());
    unsigned char* dst = buffer.data();
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        std::memcpy(dst + (static_cast<size_t>(y) * w + x) * 4,
                    px.bgra.data() + (static_cast<size_t>(y * step) * px.width + x * step) * 4, 4);
      }
    }
    bitmap.CopyFromBuffer(buffer);
    const ocr::OcrResult result = engine.RecognizeAsync(bitmap).get();
    const double f = k * step;
    auto box = [f](const winrt::Windows::Foundation::Rect& r, std::string& out) {
      char nums[96];
      std::snprintf(nums, sizeof(nums), "%d,%d,%d,%d", static_cast<int>(r.X * f), static_cast<int>(r.Y * f),
                    static_cast<int>(r.Width * f + 0.5), static_cast<int>(r.Height * f + 0.5));
      out += nums;
    };
    std::string out = "{\"lines\":[";
    bool first_line = true;
    for (const auto& line : result.Lines()) {
      float l = 1e9f, t = 1e9f, r = -1e9f, b = -1e9f;
      std::string words = "[";
      bool first_word = true;
      for (const auto& word : line.Words()) {
        const auto rect = word.BoundingRect();
        l = (std::min)(l, rect.X);
        t = (std::min)(t, rect.Y);
        r = (std::max)(r, rect.X + rect.Width);
        b = (std::max)(b, rect.Y + rect.Height);
        if (!first_word) words.push_back(',');
        first_word = false;
        words.push_back('[');
        box(rect, words);
        words.push_back(',');
        JsonText(words, Utf8(word.Text()));
        words.push_back(']');
      }
      words.push_back(']');
      if (first_word) continue;
      if (!first_line) out.push_back(',');
      first_line = false;
      out += "{\"text\":";
      JsonText(out, Utf8(line.Text()));
      out += ",\"box\":[";
      box(winrt::Windows::Foundation::Rect{l, t, r - l, b - t}, out);
      out += "],\"words\":" + words + "}";
    }
    out += "]}";
    char* json = static_cast<char*>(std::malloc(out.size() + 1));
    if (json != nullptr) std::memcpy(json, out.c_str(), out.size() + 1);
    return json;
  } catch (...) {
    return nullptr;
  }
}

}  // namespace

bool SottoCaptureMonitor(HMONITOR monitor, int max_side, int quality, bool ocr, SottoCapture* out) {
  std::memset(out, 0, sizeof(*out));
  MONITORINFO info{sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(monitor, &info)) {
    std::snprintf(out->error, sizeof(out->error), "monitor not found");
    return false;
  }
  out->left = info.rcMonitor.left;
  out->top = info.rcMonitor.top;
  out->screen_width = info.rcMonitor.right - info.rcMonitor.left;
  out->screen_height = info.rcMonitor.bottom - info.rcMonitor.top;
  UINT dpi_x = 96, dpi_y = 96;
  GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y);
  out->scale = dpi_x / 96.0;

  Pixels px;
  if (CaptureWgc(monitor, &px)) {
    std::snprintf(out->method, sizeof(out->method), "wgc");
  } else if (CaptureGdi(info.rcMonitor, &px)) {
    std::snprintf(out->method, sizeof(out->method), "gdi");
  } else {
    std::snprintf(out->error, sizeof(out->error), "screen capture failed");
    return false;
  }
  if (!EncodeJpeg(px, max_side, quality, out)) {
    SottoCaptureFree(out);
    std::snprintf(out->error, sizeof(out->error), "JPEG encoding failed");
    return false;
  }
  if (ocr && px.width > 0) {
    // The same scale EncodeJpeg used, so boxes land on the encoded image.
    out->ocr_json = Recognize(px, static_cast<double>(out->width) / px.width);
  }
  return true;
}

void SottoCaptureFree(SottoCapture* capture) {
  if (capture->jpeg != nullptr) std::free(capture->jpeg);
  capture->jpeg = nullptr;
  capture->jpeg_size = 0;
  if (capture->ocr_json != nullptr) std::free(capture->ocr_json);
  capture->ocr_json = nullptr;
}
