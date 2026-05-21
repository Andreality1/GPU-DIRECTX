#ifndef UNICODE
#define UNICODE
#endif

#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <chrono>
#include <vector>
#include <fstream>
#include <string>

// --- HIGH PERFORMANCE GPU EXPORTS (MinGW FIX) ---
extern "C" {
    // __declspec with double underscores is required for g++
    __declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;

}

struct ShaderConstants {
    float u_time;
    float u_resolution[2];
    float padding;
};

typedef HRESULT (WINAPI *pD3DCompile)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO*, 
    ID3DInclude*, LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**, ID3DBlob**);

ID3D11Device* device = nullptr;
ID3D11DeviceContext* context = nullptr;
IDXGISwapChain* swapChain = nullptr;
ID3D11RenderTargetView* rtv = nullptr;
ID3D11Buffer* constantBuffer = nullptr;

HRESULT CompileShader(const char* filename, const char* entryPoint, const char* profile, ID3DBlob** blob) {
    HMODULE hMod = LoadLibraryA("d3dcompiler_47.dll");
    if (!hMod) hMod = LoadLibraryA("d3dcompiler_46.dll");
    if (!hMod) hMod = LoadLibraryA("d3dcompiler_43.dll");
    if (!hMod) return E_FAIL;

    auto DynamicD3DCompile = (pD3DCompile)GetProcAddress(hMod, "D3DCompile");
    
    std::ifstream file(filename, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return E_FAIL;
    
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    file.read(buffer.data(), size);

    ID3DBlob* errorBlob = nullptr;
    HRESULT hr = DynamicD3DCompile(buffer.data(), buffer.size(), filename, nullptr, nullptr, 
                                   entryPoint, profile, 0, 0, blob, &errorBlob);
    
    if (FAILED(hr) && errorBlob) {
        MessageBoxA(NULL, (char*)errorBlob->GetBufferPointer(), "Shader Error", MB_OK);
        errorBlob->Release();
    }
    return hr;
}

void InitD3D(HWND hWnd) {
    DXGI_SWAP_CHAIN_DESC scd = {};
    scd.BufferCount = 1;
    scd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scd.OutputWindow = hWnd;
    scd.SampleDesc.Count = 1;
    scd.Windowed = TRUE;

    // --- MANUAL ADAPTER SELECTION ---
    IDXGIFactory* factory = nullptr;
    CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&factory);

    IDXGIAdapter* adapter = nullptr;
    IDXGIAdapter* dedicatedAdapter = nullptr;
    DXGI_ADAPTER_DESC bestDesc = {};

    // Iterate through all GPUs to find the one with the most Video RAM
    for (UINT i = 0; factory->EnumAdapters(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC desc;
        adapter->GetDesc(&desc);
        if (desc.DedicatedVideoMemory > bestDesc.DedicatedVideoMemory) {
            if (dedicatedAdapter) dedicatedAdapter->Release();
            dedicatedAdapter = adapter;
            bestDesc = desc;
        } else {
            adapter->Release();
        }
    }
    factory->Release();

    // Use D3D_DRIVER_TYPE_UNKNOWN when passing a physical adapter
    D3D11CreateDeviceAndSwapChain(dedicatedAdapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, 0, 
        nullptr, 0, D3D11_SDK_VERSION, &scd, &swapChain, &device, nullptr, &context);

    if (dedicatedAdapter) dedicatedAdapter->Release();

    ID3D11Texture2D* backBuffer;
    swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&backBuffer);
    device->CreateRenderTargetView(backBuffer, nullptr, &rtv);
    backBuffer->Release();

    D3D11_BUFFER_DESC bd = {};
    bd.Usage = D3D11_USAGE_DEFAULT;
    bd.ByteWidth = sizeof(ShaderConstants);
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    device->CreateBuffer(&bd, nullptr, &constantBuffer);

    ID3DBlob *vsBlob = nullptr, *psBlob = nullptr;
    if (SUCCEEDED(CompileShader("shader.hlsl", "VSMain", "vs_5_0", &vsBlob)) &&
        SUCCEEDED(CompileShader("shader.hlsl", "PSMain", "ps_5_0", &psBlob))) {

        ID3D11VertexShader* vs;
        ID3D11PixelShader* ps;
        device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), nullptr, &vs);
        device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), nullptr, &ps);

        context->VSSetShader(vs, nullptr, 0);
        context->PSSetShader(ps, nullptr, 0);
        context->PSSetConstantBuffers(0, 1, &constantBuffer);
        context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    }
}

LRESULT CALLBACK WindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProc(hWnd, message, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow) {
    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_HREDRAW | CS_VREDRAW, WindowProc, 0, 0, hInst, NULL, NULL, NULL, NULL, L"DX11MinGW", NULL };
    RegisterClassEx(&wc);
    HWND hWnd = CreateWindowEx(0, L"DX11MinGW", L"NVIDIA Dedicated GPU Mode", WS_OVERLAPPEDWINDOW, 100, 100, 800, 600, NULL, NULL, hInst, NULL);
    ShowWindow(hWnd, nShow);

    InitD3D(hWnd);

    MSG msg = {0};
    auto start = std::chrono::high_resolution_clock::now();

    while (msg.message != WM_QUIT) {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        } else {
            auto now = std::chrono::high_resolution_clock::now();
            float t = std::chrono::duration<float>(now - start).count();

            ShaderConstants consts = { t, { 800.0f, 600.0f }, 0.0f };
            context->UpdateSubresource(constantBuffer, 0, nullptr, &consts, 0, 0);

            float clear[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
            context->ClearRenderTargetView(rtv, clear);
            context->OMSetRenderTargets(1, &rtv, nullptr);
            
            D3D11_VIEWPORT vp = { 0, 0, 800, 600, 0, 1 };
            context->RSSetViewports(1, &vp);

            context->Draw(3, 0);
            swapChain->Present(1, 0);
        }
    }
    return 0;
}