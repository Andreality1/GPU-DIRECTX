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

// Structure for Constant Buffer (16-byte aligned)
struct ShaderConstants {
    float u_time;
    float u_resolution[2];
    float padding;
};

// Global DX11 Pointers
ID3D11Device* device = nullptr;
ID3D11DeviceContext* context = nullptr;
IDXGISwapChain* swapChain = nullptr;
ID3D11RenderTargetView* rtv = nullptr;
ID3D11Buffer* constantBuffer = nullptr;

// Type definition for dynamic DLL loading
typedef HRESULT (WINAPI *pD3DCompile)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO*, 
    ID3DInclude*, LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**, ID3DBlob**);

HRESULT CompileShader(const char* filename, const char* entryPoint, const char* profile, ID3DBlob** blob) {
    HMODULE hMod = LoadLibraryA("d3dcompiler_47.dll");
    if (!hMod) hMod = LoadLibraryA("d3dcompiler_46.dll");
    if (!hMod) hMod = LoadLibraryA("d3dcompiler_43.dll");
    
    if (!hMod) {
        MessageBoxA(NULL, "D3DCompiler DLL not found! Try installing DirectX End-User Runtimes.", "Error", MB_OK);
        return E_FAIL;
    }

    auto DynamicD3DCompile = (pD3DCompile)GetProcAddress(hMod, "D3DCompile");
    
    std::ifstream file(filename, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        std::string err = "Cannot find "; err += filename;
        MessageBoxA(NULL, err.c_str(), "File Error", MB_OK);
        return E_FAIL;
    }
    
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    file.read(buffer.data(), size);

    ID3DBlob* errorBlob = nullptr;
    HRESULT hr = DynamicD3DCompile(buffer.data(), buffer.size(), filename, nullptr, nullptr, 
                                   entryPoint, profile, 0, 0, blob, &errorBlob);
    
    if (FAILED(hr)) {
        if (errorBlob) {
            MessageBoxA(NULL, (char*)errorBlob->GetBufferPointer(), "HLSL Error", MB_OK);
            errorBlob->Release();
        }
        return hr;
    }
    return S_OK;
}

void InitD3D(HWND hWnd) {
    DXGI_SWAP_CHAIN_DESC scd = {};
    scd.BufferCount = 1;
    scd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scd.OutputWindow = hWnd;
    scd.SampleDesc.Count = 1;
    scd.Windowed = TRUE;

    D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0, 
        D3D11_SDK_VERSION, &scd, &swapChain, &device, nullptr, &context);

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
    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_HREDRAW | CS_VREDRAW, WindowProc, 0, 0, hInst, NULL, NULL, NULL, NULL, L"DX11", NULL };
    RegisterClassEx(&wc);
    HWND hWnd = CreateWindowEx(0, L"DX11", L"Shader Pattern", WS_OVERLAPPEDWINDOW, 100, 100, 800, 600, NULL, NULL, hInst, NULL);
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

            float clear[4] = { 0.1f, 0.1f, 0.1f, 1.0f };
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