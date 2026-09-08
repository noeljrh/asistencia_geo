// js/login-web.js
async function loginWeb() {
  const resp = await fetch('http://192.168.40.150:3000/api/auth/login', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'test@local', password: 'devpassword' })
  });
  return resp.json();
}

async function refreshWeb() {
  const resp = await fetch('http://192.168.40.150:3000/api/auth/refresh', {
    method: 'POST',
    credentials: 'include'
  });
  return resp.json();
}

