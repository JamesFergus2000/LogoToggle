// 3D MacBook Pro for the scroll story. Falls back to the SVG drawing if WebGL
// or the model isn't available. Listens for `lt:mode` events from app.js.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

// ---- tuning knobs (all the look lives here) ----
const LOOK = {
  exposure: 0.9,
  envIntensity: 0.9,      // studio HDRI reflections on the aluminium and glass
  keyLight: 0.6,          // soft key from front-right (mainly for the shadow)
  logoOn: 1.35,           // emissive strength of the lit logo (>1 so only it blooms)
  bloomStrength: 0.3,
  bloomRadius: 0.1,
  bloomThreshold: 1.0,    // only things brighter than white bloom = only the logo
  shadowOpacity: 0.55,
  fov: 24,
};
// Camera shots per scroll step: [azimuth°, elevation°, distance m] around the
// centre of the Mac; azimuth 0 = looking straight at the back of the lid.
const SHOTS = {
  intro:   [-30, 14, 1.15],
  off:     [0, 10, 1.0],
  on:      [24, 12, 1.0],
  breathe: [-16, 8, 0.85],
  strobe:  [32, 18, 1.1],
  clap:    [-24, 16, 1.05],
  outro:   [-42, 22, 1.5],   // behind the install section: calm and wide
};

const stage = document.getElementById('stage');
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function webglOK() {
  try { return !!document.createElement('canvas').getContext('webgl2'); } catch { return false; }
}
if (stage && webglOK()) init().catch((e) => console.warn('3D MacBook unavailable, using drawing:', e));

async function init() {
  const canvas = document.createElement('canvas');
  canvas.className = 'mbp3d';
  canvas.setAttribute('aria-hidden', 'true');

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.toneMapping = THREE.AgXToneMapping;
  renderer.toneMappingExposure = LOOK.exposure;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x000000);

  // Real studio lighting from a photographic HDRI (Poly Haven, CC0). Used for
  // lighting/reflections only; the background stays black.
  const pmrem = new THREE.PMREMGenerator(renderer);
  const base = document.baseURI;
  const [hdr, gltf] = await Promise.all([
    new RGBELoader().loadAsync(new URL('models/studio.hdr', base).href),
    new GLTFLoader().setMeshoptDecoder(MeshoptDecoder).loadAsync(new URL('models/macbook-pro-14.glb', base).href),
  ]);
  scene.environment = pmrem.fromEquirectangular(hdr).texture;
  scene.environmentIntensity = LOOK.envIntensity;
  scene.environmentRotation = new THREE.Euler(0, Math.PI * 0.7, 0);
  hdr.dispose();

  const key = new THREE.DirectionalLight(0xffffff, LOOK.keyLight);
  key.position.set(0.5, 1.4, 0.6);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  key.shadow.camera.near = 0.5; key.shadow.camera.far = 3;
  key.shadow.camera.left = key.shadow.camera.bottom = -0.35;
  key.shadow.camera.right = key.shadow.camera.top = 0.35;
  key.shadow.radius = 8;
  key.shadow.bias = -0.0004;
  scene.add(key);

  // Invisible floor: only the soft shadow shows, so there's no visible edge.
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(4, 4), new THREE.ShadowMaterial({ opacity: LOOK.shadowOpacity }));
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -0.0095;
  floor.receiveShadow = true;
  scene.add(floor);

  // ---- the model ----
  const model = gltf.scene;
  let logoMat = null;
  let logoMesh = null;
  model.traverse((o) => {
    if (!o.isMesh) return;
    o.castShadow = true;
    const m = o.material;
    if (!m) return;
    if (m.name === 'Logo') { logoMat = m; logoMesh = o; }
    if (m.name === 'Screen') m.envMapIntensity = 1.4;
  });
  if (!logoMat) throw new Error('logo material not found');
  logoMat.color.set(0xffffff);
  logoMat.emissive.set(0xfff6ea);
  logoMat.toneMapped = false; // lets the lit logo exceed white, so only it blooms
  logoMat.polygonOffset = true; // the logo is flush with the lid: win the depth test
  logoMat.polygonOffsetFactor = -2;
  logoMat.polygonOffsetUnits = -2;
  logoMat.metalness = 0.5; // constant finish: glossy dark when off, milky white when lit
  logoMat.roughness = 0.22;
  logoMesh.castShadow = false;
  scene.add(model);
  model.updateMatrixWorld(true);

  const macBox = new THREE.Box3().setFromObject(model);
  const centre = macBox.getCenter(new THREE.Vector3());
  const logoPos = new THREE.Box3().setFromObject(logoMesh).getCenter(new THREE.Vector3());


  // ---- bloom (logo only, thanks to the threshold) ----
  // near/far kept tight for depth precision (stops the logo flickering against the lid)
  const camera = new THREE.PerspectiveCamera(LOOK.fov, 1, 0.05, 6);
  // Render through an anti-aliased (MSAA) target: the composer otherwise drops anti-aliasing.
  const rt = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 4 });
  const composer = new EffectComposer(renderer, rt);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(1, 1), LOOK.bloomStrength, LOOK.bloomRadius, LOOK.bloomThreshold);
  bloom.highPassUniforms.smoothWidth.value = 0.9; // soft knee: glow fades in with the light, no popping
  composer.addPass(bloom);
  composer.addPass(new OutputPass());

  // ---- camera ----
  const lookAt = centre.clone().add(new THREE.Vector3(0, 0.01, -0.03));
  function shotPosition([az, el, dist], aspect) {
    const a = THREE.MathUtils.degToRad(az);
    const e = THREE.MathUtils.degToRad(el);
    const d = dist * (aspect < 1 ? 1.45 : 1); // tall/narrow screens: step back
    return lookAt.clone().add(new THREE.Vector3(Math.sin(a) * Math.cos(e), Math.sin(e), -Math.cos(a) * Math.cos(e)).multiplyScalar(d));
  }
  let shot = 'intro';

  // ---- light modes ----
  let mode = document.body.dataset.mode || 'breathe';
  let modeStart = performance.now();
  document.addEventListener('lt:mode', (e) => {
    mode = e.detail;
    modeStart = performance.now();
    shot = document.body.dataset.shot || mode;
  });
  const breathePeriod = () => (parseFloat(getComputedStyle(document.body).getPropertyValue('--breathe')) || 4) * 1000;
  function targetLevel(now) {
    const t = now - modeStart;
    if (mode === 'off') return 0;
    if (mode === 'on') return 1;
    if (reduceMotion) return 0.8;
    if (mode === 'strobe') return Math.floor(t / 400) % 2 === 0 ? 1 : 0;
    if (mode === 'clap') return Math.floor(t / 1800) % 2 === 0 ? 0 : 1;   // a double clap every 1.8 s
    const p = (t % breathePeriod()) / breathePeriod();
    return 0.04 + 0.96 * (0.5 - 0.5 * Math.cos(p * Math.PI * 2));
  }

  // ---- sizing ----
  function resize() {
    const w = stage.clientWidth;
    const h = stage.clientHeight;
    renderer.setSize(w, h, false);
    composer.setSize(w, h);
    camera.aspect = w / h;
    // Wide screens: Mac sits left of centre (cards float on the right).
    // Tall screens: Mac sits higher (cards float below).
    if (w / h > 1.1) camera.setViewOffset(w, h, w * 0.17, 0, w, h);
    else camera.setViewOffset(w, h, 0, h * 0.2, w, h);
    camera.updateProjectionMatrix();
  }
  new ResizeObserver(resize).observe(stage);
  resize();
  camera.position.copy(shotPosition(SHOTS.intro, camera.aspect));
  camera.lookAt(lookAt);

  // ---- render loop (paused when off-screen) ----
  let visible = true;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(stage);
  const desired = new THREE.Vector3();
  let level = 1;
  let last = performance.now();
  function frame(now) {
    requestAnimationFrame(frame);
    if (!visible) return;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;

    const tl = targetLevel(now);
    // Strobe: very short ramps (like the real LED) instead of a hard 1-frame cut.
    level += (tl - level) * Math.min(1, dt * (mode === 'strobe' ? 30 : 6));
    // Unlit: the logo is just polished dark metal. Lit: bright, crisp, with bloom.
    const eased = level * level * (3 - 2 * level); // smoothstep: gentle at both ends
    logoMat.emissiveIntensity = eased * LOOK.logoOn;
    logoMat.color.setScalar(0.03 + eased * 0.85);

    desired.copy(shotPosition(SHOTS[shot] || SHOTS.intro, camera.aspect));
    if (!reduceMotion) desired.x += Math.sin(now / 5000) * 0.02;
    camera.position.lerp(desired, reduceMotion ? 1 : Math.min(1, dt * 2));
    camera.lookAt(lookAt);

    composer.render();
  }
  stage.prepend(canvas);
  stage.classList.add('has-3d');
  requestAnimationFrame(frame);
}
