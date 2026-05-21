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

// Constant Buffer Structure (Must be 16-byte aligned)
struct ShaderData {
    float time;
    float padding[3]; 
};

// Global DirectX Resources
ID3D11Device*           device      = nullptr;
ID3D11DeviceContext*    ctx         = nullptr;
IDXGISwapChain*         swapChain   = nullptr;
ID3D11RenderTargetView* mainRTV     = nullptr;
ID3D11PixelShader*      pShader     = nullptr;
ID3D11VertexShader*     pVS         = nullptr;
ID3D11InputLayout*      pLayout     = nullptr;
ID3D11Buffer*           pVBuffer    = nullptr;
ID3D11Buffer*           pCBuffer    = nullptr;

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

    // 3. Setup Full-Screen Quad
    float vertices[] = { 
        -1.0f,  1.0f, 0.0f,  1.0f,  1.0f, 0.0f, -1.0f, -1.0f, 0.0f, 
        -1.0f, -1.0f, 0.0f,  1.0f,  1.0f, 0.0f,  1.0f, -1.0f, 0.0f 
    };
    D3D11_BUFFER_DESC bd = { sizeof(vertices), D3D11_USAGE_DEFAULT, D3D11_BIND_VERTEX_BUFFER, 0, 0, 0 };
    D3D11_SUBRESOURCE_DATA sd = { vertices };
    device->CreateBuffer(&bd, &sd, &pVBuffer);

    // 4. Create Constant Buffer for Time
    D3D11_BUFFER_DESC cbd = {};
    cbd.Usage = D3D11_USAGE_DYNAMIC;
    cbd.ByteWidth = sizeof(ShaderData);
    cbd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cbd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    device->CreateBuffer(&cbd, NULL, &pCBuffer);

    // 5. Compile Shaders from Separate Files
    ID3DBlob *vsBlob, *psBlob, *errBlob = nullptr;
    HRESULT hr;

    // Compile Vertex Shader (vertex.hlsl)
    hr = D3DCompileFromFile(L"vertex.hlsl", NULL, NULL, "main", "vs_5_0", 0, 0, &vsBlob, &errBlob);
    if (FAILED(hr)) {
        if (errBlob) printf("Vertex Shader Error: %s\n", (char*)errBlob->GetBufferPointer());
        return;
    }
    device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), NULL, &pVS);

    // Create Input Layout
    D3D11_INPUT_ELEMENT_DESC ied[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0}
    };
    device->CreateInputLayout(ied, 1, vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), &pLayout);
    vsBlob->Release();

    // Compile Pixel Shader (pixel.hlsl)
    hr = D3DCompileFromFile(L"pixel.hlsl", NULL, NULL, "main", "ps_5_0", 0, 0, &psBlob, &errBlob);
    if (FAILED(hr)) {
        if (errBlob) printf("Pixel Shader Error: %s\n", (char*)errBlob->GetBufferPointer());
        return;
    }
    device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), NULL, &pShader);
    psBlob->Release();
}

void Render() {
    static float t = 0.0f;
    t += 0.016f; 

    // Update Constant Buffer
    D3D11_MAPPED_SUBRESOURCE ms;
    ctx->Map(pCBuffer, NULL, D3D11_MAP_WRITE_DISCARD, NULL, &ms);
    ShaderData* data = (ShaderData*)ms.pData;
    data->time = t;
    ctx->Unmap(pCBuffer, NULL);

    float clearColor[] = { 0.0f, 0.0f, 0.0f, 1.0f }; 
    ctx->ClearRenderTargetView(mainRTV, clearColor);
    
    D3D11_VIEWPORT vp = { 0.0f, 0.0f, 800.0f, 600.0f, 0.0f, 1.0f };
    ctx->RSSetViewports(1, &vp);

    ctx->OMSetRenderTargets(1, &mainRTV, NULL);
    UINT stride = sizeof(float) * 3, offset = 0;
    ctx->IASetVertexBuffers(0, 1, &pVBuffer, &stride, &offset);
    ctx->IASetInputLayout(pLayout);
    ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    ctx->VSSetShader(pVS, NULL, 0);
    ctx->PSSetShader(pShader, NULL, 0);
    ctx->PSSetConstantBuffers(0, 1, &pCBuffer);

    ctx->Draw(6, 0);
    swapChain->Present(1, 0);
}

LRESULT CALLBACK WindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hWnd, message, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE, LPSTR, int n) {
    WNDCLASSEXW wc = {}; 
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = L"DX11Class";
    RegisterClassExW(&wc);

    HWND hWnd = CreateWindowExW(0, L"DX11Class", L"DirectX 11 Separate Shaders", 
                                WS_OVERLAPPEDWINDOW, 100, 100, 800, 600, 
                                NULL, NULL, hInst, NULL);
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