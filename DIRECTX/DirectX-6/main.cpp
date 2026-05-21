#ifndef WINVER
#define WINVER 0x0601
#define _WIN32_WINNT 0x0601
#endif

#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>

// --- MANUALLY DECLARE THE MISSING FUNCTION ---
extern "C" {
    HRESULT WINAPI D3DCompileFromFile(
        LPCWSTR pFileName,
        const D3D_SHADER_MACRO* pDefines,
        void* pInclude, 
        LPCSTR pEntrypoint,
        LPCSTR pTarget,
        UINT Flags1,
        UINT Flags2,
        ID3DBlob** ppCode,
        ID3DBlob** ppErrorMsgs
    );
}

// Global DirectX Resources
ID3D11Device*           device      = nullptr;
ID3D11DeviceContext*    ctx         = nullptr;
IDXGISwapChain*         swapChain   = nullptr;
ID3D11RenderTargetView* mainRTV     = nullptr;
ID3D11PixelShader*      pShader     = nullptr;
ID3D11VertexShader*     pVS         = nullptr;
ID3D11InputLayout*      pLayout     = nullptr;
ID3D11Buffer*           pVBuffer    = nullptr;

void InitD3D(HWND hWnd) {
    // 1. Create Device and Swap Chain
    DXGI_SWAP_CHAIN_DESC scd = {};
    scd.BufferCount = 1;
    scd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    scd.BufferDesc.Width = 800;
    scd.BufferDesc.Height = 600;
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scd.OutputWindow = hWnd;
    scd.SampleDesc.Count = 1;
    scd.Windowed = TRUE;

    D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, 
                                  D3D11_SDK_VERSION, &scd, &swapChain, &device, NULL, &ctx);

    // 2. Create Render Target View
    ID3D11Texture2D* pBackBuffer;
    swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (LPVOID*)&pBackBuffer);
    device->CreateRenderTargetView(pBackBuffer, NULL, &mainRTV);
    pBackBuffer->Release();

    // 3. Setup Quad Geometry (Full Screen)
    float vertices[] = { 
        -1.0f,  1.0f, 0.0f, 
         1.0f,  1.0f, 0.0f, 
        -1.0f, -1.0f, 0.0f, 
        -1.0f, -1.0f, 0.0f, 
         1.0f,  1.0f, 0.0f, 
         1.0f, -1.0f, 0.0f 
    };
    D3D11_BUFFER_DESC bd = { sizeof(vertices), D3D11_USAGE_DEFAULT, D3D11_BIND_VERTEX_BUFFER, 0, 0, 0 };
    D3D11_SUBRESOURCE_DATA sd = { vertices };
    device->CreateBuffer(&bd, &sd, &pVBuffer);

    // 4. Compile Shaders
    ID3DBlob *vsBlob, *psBlob, *errBlob = nullptr;
    
    // Compile Vertex Shader (Entry point "VS")
    HRESULT hr = D3DCompileFromFile(L"shader.hlsl", NULL, NULL, "VS", "vs_5_0", 0, 0, &vsBlob, &errBlob);
    if (FAILED(hr)) {
        if (errBlob) printf("VS Error: %s\n", (char*)errBlob->GetBufferPointer());
        return;
    }
    device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), NULL, &pVS);

    // Create Input Layout
    D3D11_INPUT_ELEMENT_DESC ied[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0}
    };
    device->CreateInputLayout(ied, 1, vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), &pLayout);
    vsBlob->Release();

    // Compile Pixel Shader (Entry point "PS")
    hr = D3DCompileFromFile(L"shader.hlsl", NULL, NULL, "PS", "ps_5_0", 0, 0, &psBlob, &errBlob);
    if (FAILED(hr)) {
        if (errBlob) printf("PS Error: %s\n", (char*)errBlob->GetBufferPointer());
        return;
    }
    device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), NULL, &pShader);
    psBlob->Release();
}

void Render() {
    float clearColor[] = { 0.0f, 0.0f, 0.0f, 1.0f }; 
    ctx->ClearRenderTargetView(mainRTV, clearColor);

    // Set Viewport
    D3D11_VIEWPORT vp = { 0.0f, 0.0f, 800.0f, 600.0f, 0.0f, 1.0f };
    ctx->RSSetViewports(1, &vp);

    // Bind Resources
    ctx->OMSetRenderTargets(1, &mainRTV, NULL);
    
    UINT stride = sizeof(float) * 3, offset = 0;
    ctx->IASetVertexBuffers(0, 1, &pVBuffer, &stride, &offset);
    ctx->IASetInputLayout(pLayout);
    ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    ctx->VSSetShader(pVS, NULL, 0);
    ctx->PSSetShader(pShader, NULL, 0);

    // Draw 6 vertices (2 triangles)
    ctx->Draw(6, 0);
    swapChain->Present(1, 0);
}

// Window Procedure
LRESULT CALLBACK WindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hWnd, message, wParam, lParam);
}

// Main Entry Point
int WINAPI WinMain(HINSTANCE hInst, HINSTANCE, LPSTR, int n) {
    // Explicit Wide-character class
    WNDCLASSEXW wc = {}; 
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = L"DX11Class";

    RegisterClassExW(&wc);

    HWND hWnd = CreateWindowExW(
        0, L"DX11Class", L"DirectX 11 Shader Test", 
        WS_OVERLAPPEDWINDOW, 100, 100, 800, 600, 
        NULL, NULL, hInst, NULL
    );

    if (!hWnd) return -1;

    ShowWindow(hWnd, n);
    InitD3D(hWnd);

    MSG msg = {};
    while (msg.message != WM_QUIT) {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        } else {
            Render();
        }
    }
    return (int)msg.wParam;
}