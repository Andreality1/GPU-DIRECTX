#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdlib.h>

// --- MAGIC EXPORTS FOR DEDICATED GPU ---
// Double underscore for MinGW/GCC compatibility
extern "C" {
    __declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
    __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}

// Constant Buffer (Matches the pixel.hlsl struct)
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

// Helper: Load file into memory for D3DCompile
HRESULT LoadShaderFile(const wchar_t* path, char** outData, size_t* outSize) {
    HANDLE hFile = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return E_FAIL;
    DWORD size = GetFileSize(hFile, NULL);
    *outData = (char*)malloc(size + 1);
    DWORD read;
    ReadFile(hFile, *outData, size, &read, NULL);
    (*outData)[size] = '\0'; // Null terminator for safety
    *outSize = size;
    CloseHandle(hFile);
    return S_OK;
}

// Find the High-Performance GPU
IDXGIAdapter* GetDedicatedAdapter() {
    IDXGIFactory* factory = nullptr;
    CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&factory);
    IDXGIAdapter* adapter = nullptr, *bestAdapter = nullptr;
    SIZE_T maxMemory = 0;

    for (UINT i = 0; factory->EnumAdapters(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC desc;
        adapter->GetDesc(&desc);
        if (desc.DedicatedVideoMemory > maxMemory) {
            maxMemory = desc.DedicatedVideoMemory;
            if (bestAdapter) bestAdapter->Release();
            bestAdapter = adapter;
        } else {
            adapter->Release();
        }
    }
    factory->Release();
    return bestAdapter;
}

void InitShaders() {
    ID3DBlob *vsBlob = nullptr, *psBlob = nullptr, *err = nullptr;
    char* data = nullptr;
    size_t size = 0;

    // 1. Compile Vertex Shader from memory
    if (SUCCEEDED(LoadShaderFile(L"vertex.hlsl", &data, &size))) {
        D3DCompile(data, size, "vertex.hlsl", NULL, NULL, "main", "vs_5_0", 0, 0, &vsBlob, &err);
        if (vsBlob) {
            g_device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), NULL, &g_vertexShader);
            vsBlob->Release();
        }
        free(data);
    }

    // 2. Compile Pixel Shader from memory
    if (SUCCEEDED(LoadShaderFile(L"pixel.hlsl", &data, &size))) {
        D3DCompile(data, size, "pixel.hlsl", NULL, NULL, "main", "ps_5_0", 0, 0, &psBlob, &err);
        if (psBlob) {
            g_device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), NULL, &g_pixelShader);
            psBlob->Release();
        } else if (err) {
            // Output errors to console/debug if shader fails
            OutputDebugStringA((char*)err->GetBufferPointer());
            err->Release();
        }
        free(data);
    }

    // 3. Create Constant Buffer for u_time
    D3D11_BUFFER_DESC bd = {};
    bd.Usage = D3D11_USAGE_DEFAULT;
    bd.ByteWidth = (sizeof(ShaderData) + 15) & ~15; // Ensure 16-byte alignment
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    g_device->CreateBuffer(&bd, NULL, &g_constantBuffer);
}

LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show) {
    // 1. Setup Window (Unicode)
    WNDCLASSW wc = {0}; 
    wc.lpfnWndProc = WndProc; 
    wc.hInstance = inst; 
    wc.lpszClassName = L"DX11_CLASS";
    RegisterClassW(&wc);

    HWND hwnd = CreateWindowExW(0, L"DX11_CLASS", L"NURBS - Dedicated GPU", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 
                                100, 100, 1280, 720, 0, 0, inst, 0);

    // 2. Create Device on Dedicated Adapter
    IDXGIAdapter* adapter = GetDedicatedAdapter();
    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 1; 
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; 
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1; 
    sd.Windowed = TRUE;
    
    D3D11CreateDeviceAndSwapChain(adapter, D3D_DRIVER_TYPE_UNKNOWN, NULL, 0, NULL, 0, D3D11_SDK_VERSION, 
                                  &sd, &g_swapChain, &g_device, NULL, &g_context);
    if(adapter) adapter->Release();

    // Render Target
    ID3D11Texture2D* bb; 
    g_swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&bb);
    g_device->CreateRenderTargetView(bb, NULL, &g_renderTargetView);
    bb->Release();

    InitShaders();

    // 3. Loop
    MSG msg = {0};
    DWORD start = GetTickCount();
    
    while (msg.message != WM_QUIT) {
        if (PeekMessage(&msg, 0, 0, 0, PM_REMOVE)) { 
            TranslateMessage(&msg); 
            DispatchMessage(&msg); 
        }
        else {
            float t = (GetTickCount() - start) / 1000.0f;
            float clearCol[4] = {0.0f, 0.0f, 0.0f, 1.0f};
            g_context->ClearRenderTargetView(g_renderTargetView, clearCol);
            
            // Update time
            ShaderData cb = { t, {0,0,0} };
            g_context->UpdateSubresource(g_constantBuffer, 0, NULL, &cb, 0, 0);
            
            // Set Pipeline
            g_context->VSSetShader(g_vertexShader, NULL, 0);
            g_context->PSSetShader(g_pixelShader, NULL, 0);
            g_context->PSSetConstantBuffers(0, 1, &g_constantBuffer);
            g_context->OMSetRenderTargets(1, &g_renderTargetView, NULL);
            
            D3D11_VIEWPORT vp = {0.0f, 0.0f, 1280.0f, 720.0f, 0.0f, 1.0f};
            g_context->RSSetViewports(1, &vp);
            
            g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            g_context->Draw(3, 0); 
            g_swapChain->Present(1, 0);
        }
    }
    return 0;
}