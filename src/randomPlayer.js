// Jugador al azar: nombre, apodo y número de camiseta (la cara la pone randomFace).
// rnd se puede reemplazar en los tests para que el resultado sea fijo.
const FIRST = [
  'Juan', 'Martín', 'Lucas', 'Matías', 'Nicolás', 'Santiago', 'Facundo', 'Diego', 'Gonzalo', 'Agustín',
  'Franco', 'Tomás', 'Joaquín', 'Ezequiel', 'Leandro', 'Pablo', 'Federico', 'Ignacio', 'Emiliano', 'Rodrigo',
  'Maximiliano', 'Lautaro', 'Bruno', 'Cristian', 'Hernán', 'Sebastián', 'Mariano', 'Damián', 'Gastón', 'Ramiro',
];
const LAST = [
  'González', 'Rodríguez', 'Gómez', 'Fernández', 'López', 'Díaz', 'Martínez', 'Pérez', 'García', 'Sánchez',
  'Romero', 'Sosa', 'Álvarez', 'Torres', 'Ruiz', 'Ramírez', 'Flores', 'Acosta', 'Benítez', 'Medina',
  'Herrera', 'Suárez', 'Aguirre', 'Giménez', 'Molina', 'Silva', 'Castro', 'Rojas', 'Ortiz', 'Núñez',
];
const NICK = [
  'Pulga', 'Tanque', 'Chino', 'Flaco', 'Ruso', 'Pato', 'Toto', 'Mono', 'Colo', 'Negro',
  'Turco', 'Pocho', 'Tucu', 'Cabezón', 'Pipa', 'Burrito', 'Muñeco', 'Loco', 'Chapa', 'Polaco',
  'Gringo', 'Topo', 'Lechuga', 'Rata', 'Pela', 'Cholo', 'Chapu', 'Manco', 'Uruguayo', 'Mago',
];

const pick = (arr, rnd) => arr[Math.floor(rnd() * arr.length) % arr.length];

// taken: números de camiseta ya usados en el equipo (no se repiten si queda alguno libre).
export function randomPlayer(taken = [], rnd = Math.random) {
  const used = new Set(taken.map((n) => String(n)));
  const free = Array.from({ length: 99 }, (_, i) => String(i + 1)).filter((n) => !used.has(n));
  return {
    name: `${pick(FIRST, rnd)} ${pick(LAST, rnd)}`,
    nickname: pick(NICK, rnd),
    number: free.length ? pick(free, rnd) : '',
  };
}
