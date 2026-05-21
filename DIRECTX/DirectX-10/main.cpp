#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <vector>
#include <stdlib.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

// --- GPU EXPORTS ---
extern "C" {
    __declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
    __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}

struct ShaderUnit {
    ID3D11VertexShader* vs = nullptr;
    ID3D11PixelShader*  ps = nullptr;
    void Release() { if (vs) vs->Release(); if (ps) ps->Release(); }
};

struct ShaderData {
    float u_time;
    float padding[3];
};

// Globals
ID3D11Device*           g_device = nullptr;
ID3D11DeviceContext*    g_context = nullptr;
IDXGISwapChain*         g_swapChain = nullptr;
ID3D11RenderTargetView* g_renderTargetView = nullptr;
ID3D11Buffer*           g_constantBuffer = nullptr;
std::vector<ShaderUnit> g_units;

// --- HELPERS ---

HRESULT LoadShaderFile(const wchar_t* path, char** outData, size_t* outSize) {
    HANDLE hFile = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return E_FAIL;
    DWORD size = GetFileSize(hFile, NULL);
    *outData = (char*)malloc(size + 1);
    DWORD read;
    ReadFile(hFile, *outData, size, &read, NULL);
    (*outData)[size] = '\0';
    *outSize = size;
    CloseHandle(hFile);
    return S_OK;
}

void CreateUnit(const wchar_t* vsPath, const wchar_t* psPath) {
    ShaderUnit unit;
    ID3DBlob *vsBlob = nullptr, *psBlob = nullptr, *err = nullptr;
    char* data = nullptr;
    size_t size = 0;

    // Compile VS
    if (SUCCEEDED(LoadShaderFile(vsPath, &data, &size))) {
        if (FAILED(D3DCompile(data, size, NULL, NULL, NULL, "main", "vs_5_0", 0, 0, &vsBlob, &err))) {
            if (err) { OutputDebugStringA((char*)err->GetBufferPointer()); err->Release(); }
        } else {
            g_device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), NULL, &unit.vs);
            vsBlob->Release();
        }
        free(data);
    }

    // Compile PS
    if (SUCCEEDED(LoadShaderFile(psPath, &data, &size))) {
        if (FAILED(D3DCompile(data, size, NULL, NULL, NULL, "main", "ps_5_0", 0, 0, &psBlob, &err))) {
            if (err) { OutputDebugStringA((char*)err->GetBufferPointer()); err->Release(); }
        } else {
            g_device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), NULL, &unit.ps);
            psBlob->Release();
        }
        free(data);
    }
    g_units.push_back(unit);
}

void Cleanup() {
    for (auto& u : g_units) u.Release();
    if (g_constantBuffer)   g_constantBuffer->Release();
    if (g_renderTargetView) g_renderTargetView->Release();
    if (g_swapChain)        g_swapChain->Release();
    if (g_context)          g_context->Release();
    if (g_device)           g_device->Release();
}

LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

// --- MAIN ---

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show) {
    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = L"DX11_MULTI";
    RegisterClassW(&wc);

    HWND hwnd = CreateWindowExW(0, L"DX11_MULTI", L"Multi-Shader Viewports", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 
                                100, 100, 1280, 720, 0, 0, inst, 0);

    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 1;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;

    D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, 
                                  &sd, &g_swapChain, &g_device, NULL, &g_context);

    ID3D11Texture2D* bb;
    g_swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&bb);
    g_device->CreateRenderTargetView(bb, NULL, &g_renderTargetView);
    bb->Release();

    // Constant Buffer for time
    D3D11_BUFFER_DESC bd = {16, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
    g_device->CreateBuffer(&bd, NULL, &g_constantBuffer);

    // Initialize units
    CreateUnit(L"vertex.hlsl", L"pixel1.hlsl");
    CreateUnit(L"vertex.hlsl", L"pixel2.hlsl");

    MSG msg = {0};
    LARGE_INTEGER freq, start;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&start);

    while (msg.message != WM_QUIT) {
        if (PeekMessage(&msg, 0, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        } else {
            LARGE_INTEGER now;
            QueryPerformanceCounter(&now);
            float t = (float)(now.QuadPart - start.QuadPart) / freq.QuadPart;

            float clearCol[4] = {0, 0, 0, 1};
            g_context->ClearRenderTargetView(g_renderTargetView, clearCol);

            ShaderData cb = { t, {0,0,0} };
            g_context->UpdateSubresource(g_constantBuffer, 0, NULL, &cb, 0, 0);

            RECT rc; GetClientRect(hwnd, &rc);
            float w = (float)rc.right;
            float h = (float)rc.bottom;

            // Common States
            g_context->PSSetConstantBuffers(0, 1, &g_constantBuffer);
            g_context->OMSetRenderTargets(1, &g_renderTargetView, NULL);
            g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

            // Render Unit 1 (Left Half)
            if (g_units.size() > 0) {
                D3D11_VIEWPORT vp1 = { 0, 0, w / 2.0f, h, 0, 1 };
                g_context->RSSetViewports(1, &vp1);
                g_context->VSSetShader(g_units[0].vs, NULL, 0);
                g_context->PSSetShader(g_units[0].ps, NULL, 0);
                g_context->Draw(3, 0);
            }

            // Render Unit 2 (Right Half)
            if (g_units.size() > 1) {
                D3D11_VIEWPORT vp2 = { w / 2.0f, 0, w / 2.0f, h, 0, 1 };
                g_context->RSSetViewports(1, &vp2);
                g_context->VSSetShader(g_units[1].vs, NULL, 0);
                g_context->PSSetShader(g_units[1].ps, NULL, 0);
                g_context->Draw(3, 0);
            }

            g_swapChain->Present(1, 0);
        }
    }

    Cleanup();
    return 0;
}