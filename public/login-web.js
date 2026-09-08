// login-web.js
async function loginWeb() {
  const resp = await fetch('http://localhost:3000/api/auth/login', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'test@local', password: 'devpassword' })
  });
  const data = await resp.json();
  console.log('login web:', data);
}

async function refreshWeb() {
  const resp = await fetch('http://localhost:3000/api/auth/refresh', {
    method: 'POST',
    credentials: 'include'
  });
  console.log(await resp.json());
}

// Llamadas de prueba (descomenta para ejecutar automáticamente)
// loginWeb();
// refreshWeb();
