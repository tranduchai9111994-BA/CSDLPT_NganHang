const fs = require('fs');
const path = require('path');

const routesDir = path.join(__dirname, 'APP_NGANHANG', 'routes');
const files = fs.readdirSync(routesDir).filter(f => f.endsWith('.js') && f !== 'auth.js');

files.forEach(file => {
  const filePath = path.join(routesDir, file);
  let content = fs.readFileSync(filePath, 'utf8');

  // Replace querySQL(server, ...) -> querySQL(req, server, ...)
  content = content.replace(/querySQL\s*\(\s*server\s*,/g, 'querySQL(req, server,');
  content = content.replace(/querySQL\s*\(\s*'TRACUU'\s*,/g, "querySQL(req, 'TRACUU',");
  
  // Replace execSP(server, ...) -> execSP(req, server, ...)
  content = content.replace(/execSP\s*\(\s*server\s*,/g, 'execSP(req, server,');
  
  // Add req to sinhSOTK if it's there
  if (content.includes('function sinhSOTK(serverKey)')) {
     content = content.replace(/function sinhSOTK\(serverKey\)/g, 'function sinhSOTK(req, serverKey)');
     content = content.replace(/sinhSOTK\(server\)/g, 'sinhSOTK(req, server)');
     content = content.replace(/querySQL\(serverKey/g, 'querySQL(req, serverKey');
  }

  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Updated ' + file);
});
