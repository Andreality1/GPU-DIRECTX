#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdlib.h>

// Link libraries via pragma (works in MSVC)
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

// --- MAGIC EXPORTS FOR DEDICATED GPU ---
extern "C" {
    __declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
    __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}

struct ShaderData {
    float u_time;
    float padding[3]; 
};

// Global DirectX Objects
ID3D11Device*           g_device = nullptr;
ID3D11DeviceContext*    g_context = nullptr;
IDXGISwapChain*         g_swapChain = nullptr;
ID3D11RenderTargetView* g_renderTargetView = nullptr;
ID3D11VertexShader*     g_vertexShader = nullptr;
ID3D11PixelShader*      g_pixelShader = nullptr;
ID3D11Buffer*           g_constantBuffer = nullptr;

// --- MEMORY MANAGEMENT: CLEANUP ---
void Cleanup() {
    if (g_context) g_context->ClearState(); // Resets pipeline
    if (g_constantBuffer)   g_constantBuffer->Release();
    if (g_pixelShader)      g_pixelShader->Release();
    if (g_vertexShader)     g_vertexShader->Release();
    if (g_renderTargetView) g_renderTargetView->Release();
    if (g_swapChain)        g_swapChain->Release();
    if (g_context)          g_context->Release();
    if (g_device)           g_device->Release();
}

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

void InitShaders() {
    ID3DBlob *vsBlob = nullptr, *psBlob = nullptr, *err = nullptr;
    char* data = nullptr;
    size_t size = 0;

    // 1. Vertex Shader
    if (SUCCEEDED(LoadShaderFile(L"vertex.hlsl", &data, &size))) {
        if (FAILED(D3DCompile(data, size, "vertex.hlsl", NULL, NULL, "main", "vs_5_0", 0, 0, &vsBlob, &err))) {
            if (err) { OutputDebugStringA((char*)err->GetBufferPointer()); err->Release(); }
        } else {
            g_device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), NULL, &g_vertexShader);
            vsBlob->Release();
        }
        free(data);
    }

    // 2. Pixel Shader
    if (SUCCEEDED(LoadShaderFile(L"pixel.hlsl", &data, &size))) {
        if (FAILED(D3DCompile(data, size, "pixel.hlsl", NULL, NULL, "main", "ps_5_0", 0, 0, &psBlob, &err))) {
            if (err) { OutputDebugStringA((char*)err->GetBufferPointer()); err->Release(); }
        } else {
            g_device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), NULL, &g_pixelShader);
            psBlob->Release();
        }
        free(data);
    }

    // 3. Constant Buffer
    D3D11_BUFFER_DESC bd = {};
    bd.Usage = D3D11_USAGE_DEFAULT;
    bd.ByteWidth = 16; // ShaderData is 16 bytes
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    g_device->CreateBuffer(&bd, NULL, &g_constantBuffer);
}

LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_DESTROY: 
            PostQuitMessage(0); 
            return 0;
        case WM_SIZE:
            if (g_swapChain && w != SIZE_MINIMIZED) {
                // Handle resizing (Release RTV, Resize, Recreate RTV)
                if (g_renderTargetView) g_renderTargetView->Release();
                g_swapChain->ResizeBuffers(0, LOWORD(l), HIWORD(l), DXGI_FORMAT_UNKNOWN, 0);
                ID3D11Texture2D* bb;
                g_swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&bb);
                g_device->CreateRenderTargetView(bb, NULL, &g_renderTargetView);
                bb->Release();
            }
            return 0;
    }
    return DefWindowProcW(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show) {
    WNDCLASSW wc = {0}; 
    wc.lpfnWndProc = WndProc; 
    wc.hInstance = inst; 
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = L"DX11_CLASS";
    RegisterClassW(&wc);

    HWND hwnd = CreateWindowExW(0, L"DX11_CLASS", L"NURBS Shader - Optimized", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 
                                100, 100, 1280, 720, 0, 0, inst, 0);

    // SwapChain Desc
    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 2; // Better performance with flip model
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; 
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1; 
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    // Create Device (Simplified for Hardware Selection)
    D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, 
                                  D3D11_SDK_VERSION, &sd, &g_swapChain, &g_device, NULL, &g_context);

    // Initial RTV
    ID3D11Texture2D* bb; 
    g_swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&bb);
    g_device->CreateRenderTargetView(bb, NULL, &g_renderTargetView);
    bb->Release();

    InitShaders();

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
            
            // Viewport setup based on current window size
            RECT rc; GetClientRect(hwnd, &rc);
            D3D11_VIEWPORT vp = {0, 0, (float)rc.right, (float)rc.bottom, 0, 1};
            g_context->RSSetViewports(1, &vp);

            g_context->VSSetShader(g_vertexShader, NULL, 0);
            g_context->PSSetShader(g_pixelShader, NULL, 0);
            g_context->PSSetConstantBuffers(0, 1, &g_constantBuffer);
            g_context->OMSetRenderTargets(1, &g_renderTargetView, NULL);
            g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            
            g_context->Draw(3, 0); 
            g_swapChain->Present(1, 0);
        }
    }

    Cleanup(); // All resources released here
    return (int)msg.wParam;
}