/*
	Scientific Benchmark & Graphing for BigInt WASM Implementations
	
	Parameters:
	- Range: 2^5 to 2^17 digits (32-bit limbs).
	- Metric: Total runtime of 128 multiplications.
	- Visualization: Log-Log plot (Base-2 X, Base-10 Y).
	- Failure Handling: Mark with 'X', do not crash.
*/

(() => {
	'use strict';

	// --- Configuration ---

	const MODULES = [
		{ name: 'Schoolbook (O(N²))', filename: 'schoolbook.wasm' },
		{ name: 'Karatsuba (O(N^1.58))', filename: 'karatsuba.wasm' },
	];

	const MIN_POW = 1;   // 2^1 = 2 limbs
	const MAX_POW = 10;  // 2^10 = 1024 limbs (well past 10^96)
	const ITERATIONS = 100;
	const TIMEOUT_MS = 30000; // Stop if a single size takes > 30s

	const COLORS = [
		'#007bff', // Blue
		'#28a745', // Green
		'#dc3545', // Red
		'#6f42c1', // Purple
		'#fd7e14', // Orange
		'#20c997', // Teal
		'#6c757d', // Grey
	];

	// --- Utilities ---

	function $(id) { return document.getElementById(id); }

	function setStatus(text, kind = 'info') {
		const el = $('status');
		if (!el) return;
		el.textContent = text;
		el.style.backgroundColor = kind === 'err' ? '#f8d7da' : (kind === 'ok' ? '#d4edda' : '#e7f3ff');
		el.style.borderLeftColor = kind === 'err' ? '#dc3545' : (kind === 'ok' ? '#28a745' : '#007bff');
	}

	function formatMs(ms) {
		if (!Number.isFinite(ms)) return 'n/a';
		if (ms < 0.01) return `${(ms * 1000).toFixed(2)}µs`;
		if (ms < 1000) return `${ms.toFixed(1)}ms`;
		return `${(ms / 1000).toFixed(2)}s`;
	}

	// Deterministic PRNG (Xorshift32) for reproducible benchmarks
	function makeRng(seed) {
		let x = seed >>> 0;
		return function() {
			x ^= x << 13; x >>>= 0;
			x ^= x >>> 17; x >>>= 0;
			x ^= x << 5; x >>>= 0;
			return x >>> 0;
		};
	}

	function createLimbs(count, seed) {
		const rng = makeRng(seed);
		const limbs = new Uint32Array(count);
		for (let i = 0; i < count; i++) limbs[i] = rng();
		// Ensure full size by setting high bit of most significant limb
		if (count > 0) limbs[count - 1] |= 0x80000000;
		return limbs;
	}

	function bigIntFromLimbs(limbs) {
		// Optimized construction using hex strings to avoid O(N^2) BigInt math
		let hex = '';
		for (let i = limbs.length - 1; i >= 0; i--) {
			hex += limbs[i].toString(16).padStart(8, '0');
		}
		return BigInt('0x' + (hex || '0'));
	}

	// --- WASM Helpers ---

	async function loadWasm(filename) {
		const res = await fetch(filename);
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
		const bytes = await res.arrayBuffer();
		const { instance } = await WebAssembly.instantiate(bytes);
		return instance;
	}

	function ensureScratch(memory, bytesNeeded) {
		const curSize = memory.buffer.byteLength;
		// Add some padding (64 bytes)
		if (curSize < bytesNeeded + 64) {
			const growBy = Math.ceil((bytesNeeded + 64 - curSize) / 65536);
			try {
				memory.grow(growBy);
			} catch (e) {
				throw new Error(`OOM: Failed to grow memory by ${growBy} pages`);
			}
		}
		// Return pointer to the end of the buffer minus needed space (simple scratch allocator)
		// Align to 4 bytes
		return (memory.buffer.byteLength - bytesNeeded) & ~3;
	}

	function copyLimbsToWasm(instance, limbs) {
		const { memory, bigint_from_limbs } = instance.exports;
		// Format: [length, limb0, limb1, ...]
		const bytesNeeded = (limbs.length + 1) * 4;
		const ptr = ensureScratch(memory, bytesNeeded);
		const mem32 = new Uint32Array(memory.buffer);
		const idx = ptr >>> 2;
		
		mem32[idx] = limbs.length;
		mem32.set(limbs, idx + 1);
		
		return bigint_from_limbs(ptr);
	}

	// --- Benchmarking ---

	async function runBenchmark() {
		if (!('WebAssembly' in window)) {
			setStatus('WebAssembly not supported.', 'err');
			return;
		}

		// 1. Prepare Sizes
		const sizes = [];
		for (let p = MIN_POW; p <= MAX_POW; p++) {
			sizes.push({ pow: p, digits: 1 << p });
		}

		// 2. Load Modules
		setStatus('Loading modules...', 'info');
		const loadedModules = [];
		for (const m of MODULES) {
			try {
				const instance = await loadWasm(m.filename);
				// Check required exports
				if (instance.exports.reset_heap && instance.exports.bigint_karatsuba) {
					loadedModules.push({ ...m, instance });
				} else {
					console.warn(`Skipping ${m.name}: missing exports`);
				}
			} catch (e) {
				console.warn(`Failed to load ${m.name}: ${e.message}`);
			}
		}

		// 3. Generate Test Data
		setStatus('Generating test vectors...', 'info');
		// We generate one pair per size to keep memory usage reasonable, 
		// but we might need to be careful with 2^17.
		const testData = [];
		for (const s of sizes) {
			// Yield to UI
			await new Promise(r => setTimeout(r, 0));
			
			const limbsA = createLimbs(s.digits, 0x12345 ^ s.digits);
			const limbsB = createLimbs(s.digits, 0x67890 ^ s.digits);
			// Pre-convert to JS BigInt for baseline
			const biA = bigIntFromLimbs(limbsA);
			const biB = bigIntFromLimbs(limbsB);
			
			testData.push({ ...s, limbsA, limbsB, biA, biB });
		}

		// 4. Run Benchmarks
		const results = [];

		// --- JS Baseline ---
		setStatus('Benchmarking JavaScript...', 'info');
		const jsRes = { name: 'JavaScript', color: COLORS[0], data: [], failure: null };
		for (const item of testData) {
			await new Promise(r => setTimeout(r, 10));
			try {
				let dummy = 0n;
				const start = performance.now();
				for (let i = 0; i < ITERATIONS; i++) {
					// We must accumulate or use the result, otherwise V8's JIT 
					// will see "dead code" and optimize the loop away entirely!
					dummy ^= (item.biA * item.biB);
				}
				const time = performance.now() - start;
				// Prevent dummy from being optimized away
				if (dummy === 1n) console.log("ignore"); 

				jsRes.data.push({ x: item.pow, y: time });
				
				if (time > TIMEOUT_MS) throw new Error('Timeout');
			} catch (e) {
				jsRes.failure = { x: item.pow, reason: e.message };
				break;
			}
		}
		results.push(jsRes);

		// --- WASM Modules ---
		for (let i = 0; i < loadedModules.length; i++) {
			const mod = loadedModules[i];
			setStatus(`Benchmarking ${mod.name}...`, 'info');
			
			const res = { 
				name: mod.name, 
				color: COLORS[(i + 1) % COLORS.length], 
				data: [], 
				failure: null 
			};

			const { reset_heap, bigint_karatsuba } = mod.instance.exports;

			for (const item of testData) {
				await new Promise(r => setTimeout(r, 10));
				try {
					// Check if we should even try (if previous failed)
					if (res.failure) break;

					// Pre-allocate inputs ONCE
					reset_heap();
					const pA = copyLimbsToWasm(mod.instance, item.limbsA);
					const pB = copyLimbsToWasm(mod.instance, item.limbsB);
					
					// Save heap pointer so we can reset it to just after pA and pB were allocated
					const saved_heap_ptr = mod.instance.exports.heap_ptr.value;
					
					const start = performance.now();
					// Run iterations
					for (let k = 0; k < ITERATIONS; k++) {
						// Reset heap to just after inputs to avoid OOM, but keep inputs alive
						mod.instance.exports.heap_ptr.value = saved_heap_ptr;
						bigint_karatsuba(pA, pB);
					}
					const time = performance.now() - start;
					res.data.push({ x: item.pow, y: time });

					if (time > TIMEOUT_MS) throw new Error('Timeout');

				} catch (e) {
					// Mark failure at this specific size
					res.failure = { x: item.pow, reason: e.message || 'Error' };
					break;
				}
			}
			results.push(res);
		}

		setStatus('Rendering...', 'info');
		renderGraph(results, sizes);
		setStatus('Done.', 'ok');
	}

	// --- Rendering ---

	function renderGraph(seriesList, sizes) {
		const canvas = $('canvas');
		const ctx = canvas.getContext('2d');
		const W = canvas.width;
		const H = canvas.height;
		
		// Layout
		const pad = { t: 60, r: 250, b: 80, l: 80 };
		const graphW = W - pad.l - pad.r;
		const graphH = H - pad.t - pad.b;

		// Scales
		// X: Linear mapping of power (5..17) -> (0..graphW)
		const minX = MIN_POW;
		const maxX = MAX_POW;
		const scaleX = val => pad.l + ((val - minX) / (maxX - minX)) * graphW;

		// Y: Log mapping. Find min/max time.
		let minY = Infinity, maxY = -Infinity;
		seriesList.forEach(s => s.data.forEach(p => {
			if (p.y > 0) {
				minY = Math.min(minY, p.y);
				maxY = Math.max(maxY, p.y);
			}
		}));
		// Default range if empty
		if (minY === Infinity) { minY = 1; maxY = 1000; }
		
		// Add padding to Y range
		minY *= 0.9;
		maxY *= 1.1;
		const logMinY = Math.log10(Math.max(1e-9, minY));
		const logMaxY = Math.log10(maxY);
		const logRangeY = logMaxY - logMinY;

		const scaleY = ms => {
			if (ms <= 0) return pad.t + graphH; // Clamp
			const logVal = Math.log10(ms);
			const norm = (logVal - logMinY) / logRangeY;
			return pad.t + graphH - (norm * graphH);
		};

		// Clear
		ctx.fillStyle = 'white';
		ctx.fillRect(0, 0, W, H);

		// --- Grid & Axes ---
		ctx.lineWidth = 1;
		ctx.font = '14px sans-serif';
		ctx.textAlign = 'center';
		ctx.textBaseline = 'top';

		// X Axis (Powers of 2)
		ctx.strokeStyle = '#eee';
		ctx.fillStyle = '#666';
		for (let p = minX; p <= maxX; p++) {
			const x = scaleX(p);
			// Grid line
			ctx.beginPath();
			ctx.moveTo(x, pad.t);
			ctx.lineTo(x, H - pad.b);
			ctx.stroke();
			// Label
			ctx.fillText(`2^${p}`, x, H - pad.b + 10);
		}
		ctx.fillStyle = '#000';
		ctx.font = 'bold 16px sans-serif';
		ctx.fillText('Operand Size (digits / 32-bit limbs)', pad.l + graphW/2, H - 30);

		// Y Axis (Log Time)
		ctx.textAlign = 'right';
		ctx.textBaseline = 'middle';
		ctx.font = '14px sans-serif';
		
		// Generate powers of 10 ticks
		const startPow = Math.floor(logMinY);
		const endPow = Math.ceil(logMaxY);
		for (let p = startPow; p <= endPow; p++) {
			const val = Math.pow(10, p);
			const y = scaleY(val);
			if (y < pad.t || y > H - pad.b) continue;

			ctx.strokeStyle = '#ddd';
			ctx.beginPath();
			ctx.moveTo(pad.l, y);
			ctx.lineTo(W - pad.r, y);
			ctx.stroke();

			ctx.fillStyle = '#666';
			ctx.fillText(formatMs(val), pad.l - 10, y);
		}
		
		ctx.save();
		ctx.translate(20, pad.t + graphH/2);
		ctx.rotate(-Math.PI/2);
		ctx.fillStyle = '#000';
		ctx.font = 'bold 16px sans-serif';
		ctx.textAlign = 'center';
		ctx.fillText(`Total Runtime (${ITERATIONS} ops) - Log Scale`, 0, 0);
		ctx.restore();

		// --- Data ---
		ctx.lineJoin = 'round';
		ctx.lineCap = 'round';

		seriesList.forEach(series => {
			if (series.data.length === 0 && !series.failure) return;

			ctx.strokeStyle = series.color;
			ctx.fillStyle = series.color;
			ctx.lineWidth = 3;

			// Draw Line
			if (series.data.length > 1) {
				ctx.beginPath();
				const first = series.data[0];
				ctx.moveTo(scaleX(first.x), scaleY(first.y));
				for (let i = 1; i < series.data.length; i++) {
					const p = series.data[i];
					ctx.lineTo(scaleX(p.x), scaleY(p.y));
				}
				ctx.stroke();
			}

			// Draw Points
			series.data.forEach(p => {
				ctx.beginPath();
				ctx.arc(scaleX(p.x), scaleY(p.y), 4, 0, Math.PI*2);
				ctx.fill();
			});

			// Draw Failure X
			if (series.failure) {
				const x = scaleX(series.failure.x);
				// Place X at the bottom of the graph (or slightly below the last point?)
				// Standard practice: Place it on the X-axis or at the level of the last point?
				// Let's place it on the X-axis line to indicate "grounded" / "crashed".
				const y = H - pad.b; 
				
				ctx.lineWidth = 4;
				ctx.beginPath();
				const r = 8;
				ctx.moveTo(x - r, y - r);
				ctx.lineTo(x + r, y + r);
				ctx.moveTo(x + r, y - r);
				ctx.lineTo(x - r, y + r);
				ctx.stroke();
			}
		});

		// --- Legend ---
		let legY = pad.t;
		const legX = W - pad.r + 20;
		ctx.textAlign = 'left';
		ctx.font = '16px sans-serif';
		
		seriesList.forEach(series => {
			ctx.fillStyle = series.color;
			ctx.fillRect(legX, legY, 15, 15);
			
			ctx.fillStyle = '#333';
			ctx.fillText(series.name, legX + 25, legY + 12);
			
			if (series.failure) {
				ctx.fillStyle = '#d00';
				ctx.font = '12px sans-serif';
				ctx.fillText(`(Failed @ 2^${series.failure.x})`, legX + 25, legY + 28);
				ctx.font = '16px sans-serif';
				legY += 15;
			}
			
			legY += 30;
		});

		// Export
		const img = $('jpg');
		const dl = $('download');
		const url = canvas.toDataURL('image/jpeg', 0.9);
		img.src = url;
		img.style.display = 'block';
		dl.href = url;
		dl.style.display = 'inline-block';
		canvas.style.display = 'none';
	}

	// Start
	window.addEventListener('load', runBenchmark);

})();
