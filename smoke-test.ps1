# smoke-test.ps1
# Uso: powershell -ExecutionPolicy Bypass -File .\smoke-test.ps1
# Ajustes:
$baseUrl = "http://localhost:3000"
$email = "test@local"
$password = "devpassword"

# Si quieres esperar a que el access token expire, pon >0 (segundos). Si no, deja 0.
$waitForExpirySeconds = 0

Write-Output "=== 1) LOGIN ==="
$body = @{ email = $email; password = $password } | ConvertTo-Json
try {
  $resp = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/auth/login" -ContentType 'application/json' -Body $body -Verbose -SessionVariable session
  Write-Output "Login OK"
  $resp | Format-List
} catch {
  Write-Error "Login failed: $($_.Exception.Message)"
  exit 1
}

# Extra: token y longitud
$token = $resp.accessToken
if ($null -eq $token -or $token.Length -eq 0) {
  Write-Error "No accessToken returned from login."
  exit 1
}
Write-Output "Access token length: $($token.Length)"

Write-Output "`n=== 2) PROTECTED (con token) ==="
try {
  $tokenTrim = $token.Trim()
  $prot = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/protected" -Headers @{ Authorization = "Bearer $tokenTrim" } -Verbose
  Write-Output "Protected response:"
  $prot | Format-List
} catch {
  Write-Warning "Protected call with initial token failed: $($_.Exception.Message)"
}

if ($waitForExpirySeconds -gt 0) {
  Write-Output "`n=== 3) Esperando $waitForExpirySeconds segundos para simular expiración del access token ==="
  Start-Sleep -Seconds $waitForExpirySeconds

  Write-Output "`n=== 4) PROTECTED (después de esperar; puede devolver 401 si expiró) ==="
  try {
    $prot2 = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/protected" -Headers @{ Authorization = "Bearer $tokenTrim" } -Verbose
    Write-Output "Protected response after wait (unexpected if token expired):"
    $prot2 | Format-List
  } catch {
    Write-Warning "Protected call after wait failed (esperado si token expiró): $($_.Exception.Message)"
  }
}

Write-Output "`n=== 5) REFRESH usando cookie guardada en la sesión ==="
try {
  $ref = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/auth/refresh" -WebSession $session -Verbose
  Write-Output "Refresh response:"
  $ref | Format-List
  $newToken = $ref.accessToken
  if ($null -ne $newToken) {
    Write-Output "Nuevo access token length: $($newToken.Length)"
  } else {
    Write-Warning "Refresh no devolvió accessToken."
  }
} catch {
  Write-Error "Refresh failed: $($_.Exception.Message)"
}

if ($null -ne $newToken -and $newToken.Length -gt 0) {
  Write-Output "`n=== 6) PROTECTED con nuevo token (reintento) ==="
  try {
    $prot3 = Invoke-RestMethod -Method Get -Uri "$baseUrl/api/protected" -Headers @{ Authorization = "Bearer $newToken" } -Verbose
    Write-Output "Protected response with refreshed token:"
    $prot3 | Format-List
  } catch {
    Write-Error "Protected call with refreshed token failed: $($_.Exception.Message)"
  }
}

Write-Output "`n=== 7) LOGOUT (revocar refresh token) ==="
try {
  Invoke-RestMethod -Method Post -Uri "$baseUrl/api/auth/logout" -WebSession $session -Verbose
  Write-Output "Logout called (server should revoke refresh token / clear cookie)."
} catch {
  Write-Warning "Logout call failed (ignorable in algunos backends): $($_.Exception.Message)"
}

Write-Output "`n=== 8) INTENTAR REFRESH DESPUÉS DE LOGOUT (debe fallar) ==="
try {
  Invoke-RestMethod -Method Post -Uri "$baseUrl/api/auth/refresh" -WebSession $session -Verbose
  Write-Error "Refresh devolvió token después de logout (ERROR: la revocación no funcionó como se esperaba)."
} catch {
  Write-Output "Refresh falló tras logout (esperado): $($_.Exception.Message)"
}

Write-Output "`nSmoke test finalizado."
