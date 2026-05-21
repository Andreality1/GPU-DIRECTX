#ifndef UNICODE
#define UNICODE
#endif

#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>

// Global pointers for DX resources
ID3D11Device* device = nullptr;
ID3D11DeviceContext* ctx = nullptr;
IDXGISwapChain* swapChain = nullptr;
ID3D11RenderTargetView* rtv = nullptr;
ID3D11Buffer* constantBuffer = nullptr;

struct ShaderConstants {
    float time;
    float resX, resY;
    float padding;
};

// 1. Initializing the Device and Swap Chain
void InitD3D(HWND hWnd) {
    DXGI_SWAP_CHAIN_DESC scd = {};
    scd.BufferCount = 1;                                    
    scd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;     
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;      
    scd.OutputWindow = hWnd;                                
    scd.SampleDesc.Count = 1;                               
    scd.Windowed = TRUE;                                    

    D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                  D3D11_SDK_VERSION, &scd, &swapChain, &device, NULL, &ctx);

    ID3D11Texture2D* pBackBuffer;
    swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (LPVOID*)&pBackBuffer);
    device->CreateRenderTargetView(pBackBuffer, NULL, &rtv);
    pBackBuffer->Release();
    ctx->OMSetRenderTargets(1, &rtv, NULL);

    D3D11_VIEWPORT viewport = {0, 0, 800, 600, 0, 1};
    ctx->RSSetViewports(1, &viewport);
}

// 2. The Main Loop
void Render() {
    float clearColor[] = {0.0f, 0.2f, 0.4f, 1.0f};
    ctx->ClearRenderTargetView(rtv, clearColor);

    // Update Constant Buffer (Time/Resolution)
    ShaderConstants sc = { (float)GetTickCount() / 1000.0f, 800.0f, 600.0f, 0.0f };
    // [Update Buffer logic here]

    swapChain->Present(1, 0); // VSync enabled
}

// Win32 Standard Window boilerplate...
LRESULT CALLBACK WindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProc(hWnd, message, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE, LPSTR, int nCmdShow) {
    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_HREDRAW | CS_VREDRAW, WindowProc, 0, 0, hInst, NULL, NULL, NULL, NULL, L"DX11", NULL };
    RegisterClassEx(&wc);
    HWND hWnd = CreateWindowEx(0, L"DX11", L"DirectX NURBS", WS_OVERLAPPEDWINDOW, 100, 100, 800, 600, NULL, NULL, hInst, NULL);
    ShowWindow(hWnd, nCmdShow);

    InitD3D(hWnd);

    MSG msg;
    while (true) {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) break;
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        Render();
    }
    return 0;
}