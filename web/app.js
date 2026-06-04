// private_lift_offline_engine.js

// 1. DATABASE MANAGEMENT (IndexedDB)
let db;
const DB_NAME = "PrivateLiftLocalDB";
const DB_VERSION = 1;

function initDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(DB_NAME, DB_VERSION);
        
        request.onupgradeneeded = function(event) {
            const database = event.target.result;
            
            // Store for Workout Sessions (Key: date string 'YYYY-MM-DD')
            if (!database.objectStoreNames.contains("sessions")) {
                database.createObjectStore("sessions", { keyPath: "date" });
            }
            
            // Store for Workout Sets (Key: auto-incrementing id)
            if (!database.objectStoreNames.contains("sets")) {
                const setStore = database.createObjectStore("sets", { keyPath: "id", autoIncrement: true });
                setStore.createIndex("sessionDate", "sessionDate", { unique: false });
            }
            
            // Store for Custom Routine Templates (Key: auto-incrementing id)
            if (!database.objectStoreNames.contains("templates")) {
                database.createObjectStore("templates", { keyPath: "id", autoIncrement: true });
            }
        };
        
        request.onsuccess = function(event) {
            db = event.target.result;
            console.log("IndexedDB Local database initialized successfully!");
            resolve();
        };
        
        request.onerror = function(event) {
            console.error("Database failed to open:", event.target.error);
            reject(event.target.error);
        };
    });
}

// 2. DEFAULT USER SETTINGS & LOCAL STORAGE
const DEFAULT_SETTINGS = {
    squatMax: 315,
    benchMax: 225,
    deadliftMax: 405,
    bodyWeight: 180,
    gender: "other",
    formula: "epley",
    weightUnit: "lbs",
    showRestTimer: true,
    theme: "system",
    appleHealthEnabled: false,
    useGridMode: false
};

let userSettings = { ...DEFAULT_SETTINGS };

function loadLocalSettings() {
    const saved = localStorage.getItem("privatelift_settings");
    if (saved) {
        try {
            userSettings = { ...DEFAULT_SETTINGS, ...JSON.parse(saved) };
        } catch(e) {
            userSettings = { ...DEFAULT_SETTINGS };
        }
    } else {
        userSettings = { ...DEFAULT_SETTINGS };
        saveLocalSettings();
    }
    
    // Seed default template routines if empty
    seedDefaultTemplates();
}

function saveLocalSettings() {
    localStorage.setItem("privatelift_settings", JSON.stringify(userSettings));
}

// 3. SEED STANDARD TRAINING ROUTINE TEMPLATES
function seedDefaultTemplates() {
    const seeded = localStorage.getItem("privatelift_templates_seeded");
    if (seeded) return;
    
    // Open templates database store
    const tx = db.transaction("templates", "readwrite");
    const store = tx.objectStore("templates");
    
    const defaults = [
        {
            name: "Powerlifting Big Three",
            description: "Squat, Bench, and Deadlift target weights.",
            exercises: [
                { exercise: "SQUAT", reps: 5, set_type: "working", pct: 0.85 },
                { exercise: "BENCH", reps: 5, set_type: "working", pct: 0.85 },
                { exercise: "DEADLIFT", reps: 5, set_type: "working", pct: 0.85 }
            ]
        },
        {
            name: "Squat Focus (3x5)",
            description: "Triple working sets for leg development.",
            exercises: [
                { exercise: "SQUAT", reps: 5, set_type: "working", pct: 0.85 },
                { exercise: "SQUAT", reps: 5, set_type: "working", pct: 0.85 },
                { exercise: "SQUAT", reps: 5, set_type: "working", pct: 0.85 }
            ]
        },
        {
            name: "Bench Press Volume (3x5)",
            description: "Triple working sets for upper body pushing power.",
            exercises: [
                { exercise: "BENCH", reps: 5, set_type: "working", pct: 0.85 },
                { exercise: "BENCH", reps: 5, set_type: "working", pct: 0.85 },
                { exercise: "BENCH", reps: 5, set_type: "working", pct: 0.85 }
            ]
        }
    ];
    
    defaults.forEach(t => store.add(t));
    tx.oncomplete = () => {
        localStorage.setItem("privatelift_templates_seeded", "true");
        console.log("Default routine templates seeded locally!");
    };
}

// 4. TAB STATE ROUTER (SPA Navigation)
let activeTab = "dashboard";

function switchTab(tabId) {
    activeTab = tabId;
    
    // Toggle screens
    const screens = ["dashboard", "stats", "history", "settings"];
    screens.forEach(s => {
        const el = document.getElementById(`screen-${s}`);
        if (s === tabId) {
            el.classList.remove("hidden");
        } else {
            el.classList.add("hidden");
        }
    });
    
    // Toggle navigation button styles (Desktop & Mobile)
    screens.forEach(s => {
        const desktopBtn = document.getElementById(`nav-btn-${s}`);
        const mobileBtn = document.getElementById(`mobile-btn-${s}`);
        
        const activeNavClasses = ["bg-blue-600", "text-white", "shadow-md", "border-blue-500"];
        const inactiveNavClasses = ["bg-gray-100", "dark:bg-gray-700", "text-gray-700", "dark:text-white", "border-gray-200", "dark:border-gray-600/50"];
        
        if (s === tabId) {
            desktopBtn.className = `px-4 py-2.5 rounded-lg text-xs font-black transition border shadow-md uppercase tracking-wider ${activeNavClasses.join(' ')}`;
            mobileBtn.className = "glass-nav-btn active w-full transition-all duration-300";
        } else {
            desktopBtn.className = `px-4 py-2.5 rounded-lg text-xs font-bold transition border uppercase tracking-wider ${inactiveNavClasses.join(' ')}`;
            mobileBtn.className = "glass-nav-btn inactive w-full transition-all duration-300";
        }
    });

    // Load tab-specific components
    if (tabId === "dashboard") {
        renderDashboard();
    } else if (tabId === "stats") {
        renderStats();
    } else if (tabId === "history") {
        renderHistory();
    } else if (tabId === "settings") {
        renderSettings();
    }
    
    // Smooth scroll top on switch
    window.scrollTo({ top: 0, behavior: 'instant' });
}

// 5. STRENGTH INTENSITY CALCULATIONS (Epley, Brzycki, Lander formulas)
function getE1RM(weight, reps, formula = "epley") {
    if (!weight || !reps) return 0;
    if (reps === 1) return weight;
    
    if (formula === "brzycki") {
        return Math.round(weight / (1.0278 - (0.0278 * reps)));
    } else if (formula === "lander") {
        return Math.round((100 * weight) / (101.3 - (2.6712 * reps)));
    } else { // default: epley
        return Math.round(weight * (1 + reps / 30));
    }
}

function getWeeklyProgram(percentage) {
    return {
        squat: Math.round((userSettings.squatMax * percentage) / 5) * 5,
        bench: Math.round((userSettings.benchMax * percentage) / 5) * 5,
        deadlift: Math.round((userSettings.deadliftMax * percentage) / 5) * 5
    };
}

// 6. DASHBOARD TAB
let currentIntensity = parseInt(localStorage.getItem("lastIntensity")) || 85;
let logSetType = "working";

function renderDashboard() {
    const percentage = currentIntensity / 100.0;
    const program = getWeeklyProgram(percentage);
    
    // Render Weight Cards
    const weightGrid = document.getElementById("weight-cards-container");
    const useGrid = userSettings.useGridMode || false;
    const itemClass = "w-[125px] shrink-0" + (useGrid ? "" : " snap-start");
    const cardExtraClass = "";
    
    if (useGrid) {
        weightGrid.className = "flex flex-row flex-wrap justify-center gap-3 w-full";
    } else {
        weightGrid.className = "flex flex-row overflow-x-auto gap-3 w-full no-scrollbar snap-x snap-mandatory pb-2";
    }
    
    weightGrid.innerHTML = `
        <!-- SQUAT CARD -->
        <div class="flex flex-col items-start ${itemClass}">
            <span class="text-[9px] md:text-[11px] font-black uppercase tracking-widest mb-1.5 ml-1 text-red-500">SQUAT</span>
            <div class="w-full bg-white dark:bg-gray-900 py-3 px-2 sm:px-3 md:p-5 rounded-xl border border-red-500/50 dark:border-red-500/40 border-l-[6px] border-l-red-500 glass-card-red flex flex-col items-start justify-center cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-850 transition-all duration-300 ${cardExtraClass}" onclick="fillCalc(${program.squat})">
                <div class="flex items-baseline gap-0.5 sm:gap-1">
                    <span class="text-base sm:text-2xl md:text-3xl font-black text-gray-900 dark:text-white leading-none">${program.squat}</span>
                    <span class="text-[8px] sm:text-xs text-gray-500 font-bold uppercase ml-0.5 sm:ml-1">${userSettings.weightUnit.toUpperCase()}</span>
                </div>
            </div>
        </div>
        <!-- BENCH CARD -->
        <div class="flex flex-col items-start ${itemClass}">
            <span class="text-[9px] md:text-[11px] font-black uppercase tracking-widest mb-1.5 ml-1 text-blue-500">BENCH</span>
            <div class="w-full bg-white dark:bg-gray-900 py-3 px-2 sm:px-3 md:p-5 rounded-xl border border-blue-500/50 dark:border-blue-500/40 border-l-[6px] border-l-blue-500 glass-card-blue flex flex-col items-start justify-center cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-850 transition-all duration-300 ${cardExtraClass}" onclick="fillCalc(${program.bench})">
                <div class="flex items-baseline gap-0.5 sm:gap-1">
                    <span class="text-base sm:text-2xl md:text-3xl font-black text-gray-900 dark:text-white leading-none">${program.bench}</span>
                    <span class="text-[8px] sm:text-xs text-gray-500 font-bold uppercase ml-0.5 sm:ml-1">${userSettings.weightUnit.toUpperCase()}</span>
                </div>
            </div>
        </div>
        <!-- DEADLIFT CARD -->
        <div class="flex flex-col items-start ${itemClass}">
            <span class="text-[9px] md:text-[11px] font-black uppercase tracking-widest mb-1.5 ml-1 text-green-500">DEADLIFT</span>
            <div class="w-full bg-white dark:bg-gray-900 py-3 px-2 sm:px-3 md:p-5 rounded-xl border border-green-500/50 dark:border-green-500/40 border-l-[6px] border-l-green-500 glass-card-green flex flex-col items-start justify-center cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-850 transition-all duration-300 ${cardExtraClass}" onclick="fillCalc(${program.deadlift})">
                <div class="flex items-baseline gap-0.5 sm:gap-1">
                    <span class="text-base sm:text-2xl md:text-3xl font-black text-gray-900 dark:text-white leading-none">${program.deadlift}</span>
                    <span class="text-[8px] sm:text-xs text-gray-500 font-bold uppercase ml-0.5 sm:ml-1">${userSettings.weightUnit.toUpperCase()}</span>
                </div>
            </div>
        </div>
    `;
    
    // Sync all unit labels
    document.querySelectorAll(".calc-unit-label").forEach(el => {
        el.innerText = userSettings.weightUnit.toUpperCase();
    });
    
    // Render Today's Sets list
    renderTodaySets();
    
    // Calculate plates initially
    calculatePlates();
}

function updateIntensity(val) {
    currentIntensity = parseInt(val);
    localStorage.setItem("lastIntensity", currentIntensity);
    
    const disp = document.getElementById("intensity-display");
    if (disp) disp.innerText = `${val}%`;
    
    const largeDisp = document.getElementById("intensity-large-display");
    if (largeDisp) largeDisp.innerText = `${val}%`;
    
    const percentage = val / 100.0;
    const program = getWeeklyProgram(percentage);
    
    // Quick-update weights on grid
    renderDashboard();
}

// Set type dropdown change handler inside logging box
function setLogType(type) {
    logSetType = type;
    const selectEl = document.getElementById("log-type");
    if (selectEl && selectEl.value !== type) {
        selectEl.value = type;
    }
}

function getTodayString() {
    const today = new Date();
    const yyyy = today.getFullYear();
    const mm = String(today.getMonth() + 1).padStart(2, '0');
    const dd = String(today.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
}

// Log new set submit handler
function handleLogSubmit(event) {
    event.preventDefault();
    
    const exercise = document.getElementById("log-exercise").value;
    const weight = parseInt(document.getElementById("log-weight").value);
    const reps = parseInt(document.getElementById("log-reps").value);
    const rpeVal = document.getElementById("log-rpe").value;
    const rpe = rpeVal ? parseFloat(rpeVal) : null;
    
    if (isNaN(weight) || isNaN(reps) || weight < 0 || reps <= 0) {
        alert("Please enter valid weight and rep figures.");
        return;
    }
    
    const todayStr = getTodayString();
    const calculatedE1RM = getE1RM(weight, reps, userSettings.formula);
    
    // Open transaction to write session & set
    const tx = db.transaction(["sessions", "sets"], "readwrite");
    const sessionStore = tx.objectStore("sessions");
    const setStore = tx.objectStore("sets");
    
    // Ensure session exists
    sessionStore.put({ date: todayStr, notes: "" });
    
    // Create new set
    const newSet = {
        sessionDate: todayStr,
        exercise: exercise,
        weight: weight,
        reps: reps,
        set_type: logSetType,
        rpe: rpe,
        e1rm: calculatedE1RM
    };
    
    setStore.add(newSet);
    
    tx.oncomplete = function() {
        console.log("Set successfully logged locally!");
        document.getElementById("log-set-form").reset();
        setLogType("working"); // reset to default
        
        // Re-render
        renderTodaySets();
        
        // Native Haptic feedback trigger (short pulse)
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic) {
            window.webkit.messageHandlers.haptic.postMessage("success");
        } else if (navigator.vibrate) {
            navigator.vibrate(25);
        }
        
        // Rest timer trigger
        if (userSettings.showRestTimer && logSetType !== "warmup") {
            triggerRestTimer(180); // standard 180 seconds (3 minutes)
        }
        
        // Apple Health (HealthKit) sync trigger
        if (userSettings.appleHealthEnabled && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.applehealth) {
            window.webkit.messageHandlers.applehealth.postMessage({
                action: "saveWorkout",
                date: todayStr,
                exercise: exercise,
                weight: weight,
                reps: reps,
                set_type: logSetType,
                rpe: rpe
            });
        }
    };
}

// Today's Sets partial renderer
function renderTodaySets() {
    const todayStr = getTodayString();
    const container = document.getElementById("todays-sets-container");
    container.innerHTML = "";
    
    const tx = db.transaction("sets", "readonly");
    const store = tx.objectStore("sets");
    const index = store.index("sessionDate");
    const request = index.getAll(todayStr);
    
    request.onsuccess = function(event) {
        const sets = event.target.result;
        if (!sets || sets.length === 0) {
            container.innerHTML = `<p class="text-gray-400 dark:text-gray-500 text-xs italic py-4 text-center">No sets recorded yet today. Hit the platform!</p>`;
            return;
        }
        
        // Sort sets by ID descending (newest first)
        sets.sort((a,b) => b.id - a.id);
        
        sets.forEach(set => {
            const badgeClasses = {
                warmup: "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300",
                working: "bg-blue-50 text-blue-700 border-blue-100 dark:bg-blue-900/30 dark:text-blue-300 dark:border-blue-800",
                failure: "bg-red-50 text-red-700 border-red-100 dark:bg-red-900/30 dark:text-red-300 dark:border-red-800"
            }[set.set_type];
            
            const rpeBadge = set.rpe ? `<span class="bg-purple-100 text-purple-800 dark:bg-purple-900/50 dark:text-purple-300 px-2 py-0.5 rounded text-[9px] font-black leading-none ml-1 uppercase">@${set.rpe}</span>` : "";
            
            const exerciseColorClass = {
                SQUAT: "glass-card-red border-red-500/30 dark:border-red-500/20 bg-red-500/5 dark:bg-red-500/10 border-l-4 border-l-red-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]",
                BENCH: "glass-card-blue border-blue-500/30 dark:border-blue-500/20 bg-blue-500/5 dark:bg-blue-500/10 border-l-4 border-l-blue-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]",
                DEADLIFT: "glass-card-green border-green-500/30 dark:border-green-500/20 bg-green-500/5 dark:bg-green-500/10 border-l-4 border-l-green-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]"
            }[set.exercise.toUpperCase()] || "bg-gray-50 dark:bg-gray-900/50 border-gray-200 dark:border-gray-800";
            
            const row = document.createElement("div");
            row.id = `today-set-${set.id}`;
            row.className = `${exerciseColorClass} px-4 py-3 rounded-xl border flex justify-between items-center transition-all duration-300`;
            row.innerHTML = `
                <div>
                    <div class="flex items-center gap-1">
                        <span class="text-xs font-black ${set.exercise === 'SQUAT' ? 'text-red-500' : set.exercise === 'BENCH' ? 'text-blue-500' : 'text-green-500'} uppercase">${set.exercise}</span>
                        <select onchange="updateSetType(${set.id}, this.value)" class="text-[9px] uppercase font-black px-1 py-0.5 rounded outline-none border-0 cursor-pointer ${badgeClasses}">
                            <option value="warmup" ${set.set_type === 'warmup' ? 'selected' : ''}>Warm-up</option>
                            <option value="working" ${set.set_type === 'working' ? 'selected' : ''}>Working</option>
                            <option value="failure" ${set.set_type === 'failure' ? 'selected' : ''}>Failure</option>
                        </select>
                        ${rpeBadge}
                    </div>
                    <p class="text-sm font-black text-gray-800 dark:text-gray-100 mt-1">
                        ${set.weight} ${userSettings.weightUnit.toUpperCase()} <span class="text-xs text-gray-400 font-bold">x</span> ${set.reps} reps
                    </p>
                </div>
                <div class="flex items-center gap-3">
                    <span class="text-[9px] font-bold text-gray-400 uppercase">e1RM: ${set.e1rm}</span>
                    <button onclick="deleteTodaySet(${set.id})" class="text-gray-400 hover:text-red-500 transition-colors p-1" title="Delete Set">
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                    </button>
                </div>
            `;
            container.appendChild(row);
        });
    };
}

function deleteTodaySet(setId) {
    if (!confirm("Are you sure you want to delete this logged set?")) return;
    
    const tx = db.transaction("sets", "readwrite");
    const store = tx.objectStore("sets");
    store.delete(setId);
    
    tx.oncomplete = function() {
        const el = document.getElementById(`today-set-${setId}`);
        if (el) {
            el.classList.add("scale-95", "opacity-0");
            setTimeout(() => {
                renderTodaySets();
            }, 300);
        }
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic) {
            window.webkit.messageHandlers.haptic.postMessage("medium");
        } else if (navigator.vibrate) {
            navigator.vibrate(15);
        }
    };
}

// Update log set type dynamically after logging a set
function updateSetType(setId, newType) {
    const tx = db.transaction("sets", "readwrite");
    const store = tx.objectStore("sets");
    
    store.get(setId).onsuccess = function(event) {
        const set = event.target.result;
        if (!set) return;
        
        set.set_type = newType;
        store.put(set).onsuccess = function() {
            console.log(`Set ${setId} type successfully updated to ${newType}`);
            computeBigLiftsStats();
            renderTodaySets();
            if (activeTab === "history") {
                renderHistoryList();
            } else if (activeTab === "dashboard") {
                renderDashboard();
            }
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic) {
                window.webkit.messageHandlers.haptic.postMessage("success");
            }
        };
    };
}

// 7. INTERACTIVE PLATE CALCULATOR
function fillCalc(weight) {
    document.getElementById("calc-weight-input").value = weight;
    calculatePlates();
}

function autofillCalc(exercise) {
    const program = getWeeklyProgram(currentIntensity / 100.0);
    const weight = program[exercise];
    fillCalc(weight);
}

function calculatePlates() {
    const totalWeight = parseInt(document.getElementById("calc-weight-input").value);
    const graphicContainer = document.getElementById("barbell-graphic");
    const textBreakdown = document.getElementById("plates-breakdown-text");
    
    graphicContainer.innerHTML = "";
    textBreakdown.innerText = "";
    
    if (isNaN(totalWeight) || totalWeight <= 0) {
        textBreakdown.innerText = "Enter weight above 0 to calculate.";
        return;
    }
    
    const isLbs = userSettings.weightUnit === "lbs";
    const barWeight = isLbs ? 45 : 20;
    
    if (totalWeight < barWeight) {
        textBreakdown.innerText = `Weight is less than the barbell weight (${barWeight} ${userSettings.weightUnit.toUpperCase()}).`;
        return;
    }
    
    const sideWeight = (totalWeight - barWeight) / 2;
    
    // Plate definitions (Weight, height class, Tailwind color class)
    const lbsPlatesConfig = [
        { wt: 45, h: "h-16", color: "bg-red-500 border border-red-600 text-white" },
        { wt: 35, h: "h-14", color: "bg-blue-500 border border-blue-600 text-white" },
        { wt: 25, h: "h-12", color: "bg-yellow-500 border border-yellow-600 text-black" },
        { wt: 10, h: "h-10", color: "bg-green-500 border border-green-600 text-white" },
        { wt: 5, h: "h-8", color: "bg-gray-200 border border-gray-300 text-gray-800" },
        { wt: 2.5, h: "h-6", color: "bg-black border border-gray-800 text-white" }
    ];
    
    const kgPlatesConfig = [
        { wt: 25, h: "h-16", color: "bg-red-500 border border-red-600 text-white" },
        { wt: 20, h: "h-14", color: "bg-blue-500 border border-blue-600 text-white" },
        { wt: 15, h: "h-12", color: "bg-yellow-500 border border-yellow-600 text-black" },
        { wt: 10, h: "h-10", color: "bg-green-500 border border-green-600 text-white" },
        { wt: 5, h: "h-8", color: "bg-gray-200 border border-gray-300 text-gray-800" },
        { wt: 2.5, h: "h-6", color: "bg-black border border-gray-800 text-white" },
        { wt: 1.25, h: "h-5", color: "bg-gray-400 border border-gray-500 text-white" }
    ];
    
    const config = isLbs ? lbsPlatesConfig : kgPlatesConfig;
    let remaining = sideWeight;
    const platesUsed = [];
    
    config.forEach(plate => {
        const count = Math.floor(remaining / plate.wt);
        if (count > 0) {
            for (let i = 0; i < count; i++) {
                platesUsed.push(plate);
            }
            remaining = remaining % plate.wt;
        }
    });
    
    // Draw barbell graphic
    // 1. Draw sleeve/bar base
    const sleeve = document.createElement("div");
    sleeve.className = "w-6 h-3 bg-gray-400 dark:bg-gray-600 rounded-l shrink-0";
    graphicContainer.appendChild(sleeve);
    
    // 2. Draw plates on bar
    if (platesUsed.length === 0) {
        textBreakdown.innerText = "No plates needed (Empty Barbell).";
    } else {
        const counts = {};
        platesUsed.forEach(p => {
            counts[p.wt] = (counts[p.wt] || 0) + 1;
            
            const visualPlate = document.createElement("div");
            visualPlate.className = `w-4 ${p.h} ${p.color} rounded flex items-center justify-center font-black text-[7px] select-none shrink-0 shadow-md`;
            visualPlate.innerText = p.wt;
            graphicContainer.appendChild(visualPlate);
        });
        
        // Write text list
        const textParts = Object.entries(counts).map(([wt, qty]) => `${qty}x ${wt} ${userSettings.weightUnit.toUpperCase()}`);
        textBreakdown.innerText = `Plates per side: ${textParts.join(', ')}`;
    }
    
    // 3. Draw remaining bar tip
    const barTip = document.createElement("div");
    barTip.className = "w-10 h-2 bg-gray-300 dark:bg-gray-700 rounded-r shrink-0";
    graphicContainer.appendChild(barTip);
}

// 8. BACKGROUND-SAFE AUTOMATED REST TIMER
let timerInterval;
let timerTargetEndTime = null;

function triggerRestTimer(seconds) {
    if (!userSettings.showRestTimer) return;
    if (timerInterval) clearInterval(timerInterval);
    
    timerTargetEndTime = Date.now() + seconds * 1000;
    localStorage.setItem("privatelift_timer_end", timerTargetEndTime);
    
    const capsule = document.getElementById("rest-timer-capsule");
    if (capsule) {
        capsule.classList.remove("hidden");
        // Force flow reflow for CSS transition
        void capsule.offsetWidth;
        capsule.classList.remove("scale-95", "opacity-0");
        capsule.classList.add("scale-100", "opacity-100");
    }
    
    tickRestTimer();
    timerInterval = setInterval(tickRestTimer, 100);
}
window.triggerRestTimer = triggerRestTimer;

function tickRestTimer() {
    if (!timerTargetEndTime) return;
    
    const now = Date.now();
    const remainingMs = timerTargetEndTime - now;
    
    if (remainingMs <= 0) {
        skipRestTimer();
        // Play success haptic or vibration
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic) {
            window.webkit.messageHandlers.haptic.postMessage("success");
        } else if (navigator.vibrate) {
            navigator.vibrate([100, 50, 100]);
        }
        return;
    }
    
    const totalSeconds = Math.ceil(remainingMs / 1000);
    const m = String(Math.floor(totalSeconds / 60)).padStart(2, '0');
    const s = String(totalSeconds % 60).padStart(2, '0');
    
    const countdownEl = document.getElementById("timer-countdown");
    if (countdownEl) {
        countdownEl.innerText = `${m}:${s}`;
    }
}

function skipRestTimer(e) {
    if (e) {
        e.preventDefault();
        e.stopPropagation();
    }
    
    if (timerInterval) clearInterval(timerInterval);
    timerTargetEndTime = null;
    localStorage.removeItem("privatelift_timer_end");
    
    const capsule = document.getElementById("rest-timer-capsule");
    if (capsule) {
        capsule.classList.remove("scale-100", "opacity-100");
        capsule.classList.add("scale-95", "opacity-0");
        setTimeout(() => {
            if (timerTargetEndTime === null) {
                capsule.classList.add("hidden");
            }
        }, 300);
    }
}
window.skipRestTimer = skipRestTimer;

// Check timer resume on tab wake, app return, or startup
function checkTimerResume() {
    const savedEndTime = localStorage.getItem("privatelift_timer_end");
    if (savedEndTime) {
        const endTime = parseInt(savedEndTime, 10);
        const now = Date.now();
        if (endTime > now) {
            timerTargetEndTime = endTime;
            const capsule = document.getElementById("rest-timer-capsule");
            if (capsule) {
                capsule.classList.remove("hidden");
                void capsule.offsetWidth;
                capsule.classList.remove("scale-95", "opacity-0");
                capsule.classList.add("scale-100", "opacity-100");
            }
            tickRestTimer();
            if (timerInterval) clearInterval(timerInterval);
            timerInterval = setInterval(tickRestTimer, 100);
        } else {
            localStorage.removeItem("privatelift_timer_end");
        }
    }
}
window.checkTimerResume = checkTimerResume;

document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && timerTargetEndTime) {
        tickRestTimer(); // refresh immediately
    }
});

// 9. STATS & ANALYTICS TAB
let e1rmChartInstance = null;

function renderStats() {
    const tx = db.transaction(["sessions", "sets"], "readonly");
    const sessionStore = tx.objectStore("sessions");
    const setStore = tx.objectStore("sets");
    
    // 1. Fetch total sessions count
    const sessionRequest = sessionStore.count();
    sessionRequest.onsuccess = function(e) {
        const total = e.target.result;
        document.getElementById("stats-total-sessions").innerText = total;
    };
    
    // 2. Fetch all sets for detailed metrics
    const setsRequest = setStore.getAll();
    setsRequest.onsuccess = function(e) {
        const sets = e.target.result || [];
        computeBigLiftsStats(sets);
        computeWeeklyVolumeStats(sets);
    };
}

// DOTS & Wilks formulas calculations client-side in JS
function calculateStrengthScores(peakSquat, peakBench, peakDeadlift) {
    const bw = userSettings.bodyWeight;
    const gender = userSettings.gender;
    
    // Opt-out check for 'other' / Prefer Not to Say
    if (gender !== "male" && gender !== "female" && gender !== "non_binary") {
        document.getElementById("stats-dots-score").innerText = "N/A";
        document.getElementById("stats-wilks-score").innerText = "N/A";
        return;
    }
    
    // We use the maximum of the manual settings benchmark or the actual logged peak
    const squat = Math.max(userSettings.squatMax || 0, peakSquat || 0);
    const bench = Math.max(userSettings.benchMax || 0, peakBench || 0);
    const deadlift = Math.max(userSettings.deadliftMax || 0, peakDeadlift || 0);
    const totalPl = squat + bench + deadlift;
    
    if (totalPl === 0 || !bw) {
        document.getElementById("stats-dots-score").innerText = "0.00";
        document.getElementById("stats-wilks-score").innerText = "0.00";
        return;
    }
    
    // Convert to kg for official coefficients
    const bwKg = userSettings.weightUnit === "lbs" ? bw * 0.45359237 : bw;
    const totalKg = userSettings.weightUnit === "lbs" ? totalPl * 0.45359237 : totalPl;
    
    // 1. DOTS Formula (4th-degree polynomial in denominator)
    // Denominator = A*bw^4 + B*bw^3 + C*bw^2 + D*bw + E
    // Male DOTS Coefficients:
    // A = -0.0000010930, B = 0.0007391293, C = -0.1918759221, D = 24.0900756, E = -307.75076
    // Female DOTS Coefficients:
    // A = -0.0000010706, B = 0.0005158568, C = -0.1126655495, D = 13.6175032, E = -57.96288
    const dotsDenomFemale = (-0.0000010706 * Math.pow(bwKg, 4)) + 
                            (0.0005158568 * Math.pow(bwKg, 3)) + 
                            (-0.1126655495 * Math.pow(bwKg, 2)) + 
                            (13.6175032 * bwKg) - 57.96288;
                            
    const dotsDenomMale = (-0.0000010930 * Math.pow(bwKg, 4)) + 
                          (0.0007391293 * Math.pow(bwKg, 3)) + 
                          (-0.1918759221 * Math.pow(bwKg, 2)) + 
                          (24.0900756 * bwKg) - 307.75076;
    
    const dotsFemale = dotsDenomFemale > 0 ? (totalKg * 500) / dotsDenomFemale : 0;
    const dotsMale = dotsDenomMale > 0 ? (totalKg * 500) / dotsDenomMale : 0;
    
    let dotsScore = 0;
    if (gender === "female") {
        dotsScore = dotsFemale;
    } else if (gender === "male") {
        dotsScore = dotsMale;
    } else {
        // Highly inclusive approach for Non-Binary / Other: use the exact midpoint average of male and female curves!
        dotsScore = (dotsFemale + dotsMale) / 2;
    }
    document.getElementById("stats-dots-score").innerText = dotsScore.toFixed(2);
    
    // 2. Classic Wilks Formula (5th-degree polynomial in denominator)
    // Coeff = 500 / (a + b*x + c*x^2 + d*x^3 + e*x^4 + f*x^5)
    // Male Wilks Coefficients:
    // a = -216.0475144, b = 16.2606339, c = -0.002388645, d = -0.00113732, e = 7.01863e-6, f = -1.291e-8
    // Female Wilks Coefficients:
    // a = 594.31747775582, b = -27.23842536447, c = 0.82112226871, d = -0.00930733913, e = 4.731582e-5, f = -9.054e-8
    const wilksDenomFemale = 594.31747775582 + 
                             (-27.23842536447 * bwKg) + 
                             (0.82112226871 * Math.pow(bwKg, 2)) + 
                             (-0.00930733913 * Math.pow(bwKg, 3)) + 
                             (4.731582e-5 * Math.pow(bwKg, 4)) + 
                             (-9.054e-8 * Math.pow(bwKg, 5));
                             
    const wilksDenomMale = -216.0475144 + 
                           (16.2606339 * bwKg) + 
                           (-0.002388645 * Math.pow(bwKg, 2)) + 
                           (-0.00113732 * Math.pow(bwKg, 3)) + 
                           (7.01863e-6 * Math.pow(bwKg, 4)) + 
                           (-1.291e-8 * Math.pow(bwKg, 5));
                           
    const wilksFemale = wilksDenomFemale > 0 ? totalKg * (500 / wilksDenomFemale) : 0;
    const wilksMale = wilksDenomMale > 0 ? totalKg * (500 / wilksDenomMale) : 0;
    
    let wilksScore = 0;
    if (gender === "female") {
        wilksScore = wilksFemale;
    } else if (gender === "male") {
        wilksScore = wilksMale;
    } else {
        // Highly inclusive approach for Non-Binary / Other: use the exact midpoint average of male and female curves!
        wilksScore = (wilksFemale + wilksMale) / 2;
    }
    document.getElementById("stats-wilks-score").innerText = wilksScore.toFixed(2);
}

// Compute stats card values
function computeBigLiftsStats(sets) {
    const cardsContainer = document.getElementById("stats-exercise-cards");
    cardsContainer.innerHTML = "";
    
    const exercises = ["SQUAT", "BENCH", "DEADLIFT"];
    const metrics = {
        SQUAT: { tonnage: 0, reps: 0, peak: 0 },
        BENCH: { tonnage: 0, reps: 0, peak: 0 },
        DEADLIFT: { tonnage: 0, reps: 0, peak: 0 }
    };
    
    sets.forEach(s => {
        const ex = s.exercise.toUpperCase();
        if (metrics[ex]) {
            if (s.set_type !== "warmup") {
                metrics[ex].tonnage += (s.weight * s.reps);
                metrics[ex].reps += s.reps;
                if (s.e1rm > metrics[ex].peak) {
                    metrics[ex].peak = s.e1rm;
                }
            }
        }
    });
    
    exercises.forEach(ex => {
        const labelColor = ex === "SQUAT" ? "text-red-500" : ex === "BENCH" ? "text-blue-500" : "text-green-500";
        const volColor = ex === "SQUAT" ? "text-red-400" : ex === "BENCH" ? "text-blue-400" : "text-green-400";
        
        const cardClass = {
            SQUAT: "glass-card-red border-red-500/30 dark:border-red-500/20 bg-red-500/5 dark:bg-red-500/10",
            BENCH: "glass-card-blue border-blue-500/30 dark:border-blue-500/20 bg-blue-500/5 dark:bg-blue-500/10",
            DEADLIFT: "glass-card-green border-green-500/30 dark:border-green-500/20 bg-green-500/5 dark:bg-green-500/10"
        }[ex];

        const boxClass = {
            SQUAT: "glass-card-red border-red-500/30 dark:border-red-500/20 bg-red-500/5 dark:bg-red-500/10 border-l-4 border-l-red-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]",
            BENCH: "glass-card-blue border-blue-500/30 dark:border-blue-500/20 bg-blue-500/5 dark:bg-blue-500/10 border-l-4 border-l-blue-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]",
            DEADLIFT: "glass-card-green border-green-500/30 dark:border-green-500/20 bg-green-500/5 dark:bg-green-500/10 border-l-4 border-l-green-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]"
        }[ex];
        
        const card = document.createElement("div");
        card.className = `bg-white dark:bg-gray-800 p-4 md:p-5 rounded-2xl flex flex-col md:flex-row gap-3 md:gap-4 justify-between items-stretch border border-gray-200 dark:border-gray-700 transition-all ${cardClass}`;
        card.innerHTML = `
            <div class="md:w-1/5 flex items-center justify-center md:justify-start">
                <h3 class="text-xs md:text-sm font-black ${labelColor} uppercase tracking-widest">${ex}</h3>
            </div>
            <div class="flex-grow grid grid-cols-3 gap-2.5">
                <div class="${boxClass} p-2 rounded-xl text-center flex flex-col justify-center min-w-[70px]">
                    <p class="text-[7px] md:text-[9px] text-gray-400 dark:text-gray-500 font-bold uppercase tracking-wider leading-none mb-1">Volume</p>
                    <p class="${volColor} font-black text-xs md:text-base leading-none whitespace-nowrap">${metrics[ex].tonnage} <span class="text-[7px] md:text-[9px] text-gray-500 font-bold">${userSettings.weightUnit.toUpperCase()}</span></p>
                </div>
                <div class="${boxClass} p-2 rounded-xl text-center flex flex-col justify-center min-w-[70px]">
                    <p class="text-[7px] md:text-[9px] text-gray-400 dark:text-gray-500 font-bold uppercase tracking-wider leading-none mb-1">Reps</p>
                    <p class="text-green-400 font-black text-xs md:text-base leading-none whitespace-nowrap">${metrics[ex].reps}</p>
                </div>
                <div class="${boxClass} p-2 rounded-xl text-center flex flex-col justify-center min-w-[70px]">
                    <p class="text-[7px] md:text-[9px] text-gray-400 dark:text-gray-500 font-bold uppercase tracking-wider leading-none mb-1">Peak e1RM</p>
                    <p class="text-amber-500 font-black text-xs md:text-base leading-none whitespace-nowrap">${metrics[ex].peak} <span class="text-[7px] md:text-[9px] text-gray-500 font-bold">${userSettings.weightUnit.toUpperCase()}</span></p>
                </div>
            </div>
        `;
        cardsContainer.appendChild(card);
    });
    
    // Call calculateStrengthScores with the peak lifter metrics calculated from history
    calculateStrengthScores(metrics.SQUAT.peak, metrics.BENCH.peak, metrics.DEADLIFT.peak);
}

// Compute Weekly breakdown calendar lists client-side!
function getMonday(d) {
    d = new Date(d);
    const day = d.getDay();
    const diff = d.getDate() - day + (day === 0 ? -6 : 1); // adjust when day is sunday
    return new Date(d.setDate(diff));
}

function computeWeeklyVolumeStats(sets) {
    const container = document.getElementById("stats-weekly-breakdown-container");
    container.innerHTML = "";
    
    // Group sets by ISO calendar week Monday
    const weeklyData = {};
    
    sets.forEach(s => {
        if (s.set_type === "warmup") return;
        
        const dateObj = new Date(s.sessionDate);
        const monday = getMonday(dateObj);
        const yyyy = monday.getFullYear();
        const mm = String(monday.getMonth() + 1).padStart(2, '0');
        const dd = String(monday.getDate()).padStart(2, '0');
        const mondayStr = `${yyyy}-${mm}-${dd}`;
        
        if (!weeklyData[mondayStr]) {
            weeklyData[mondayStr] = {
                SQUAT: { tonnage: 0, reps: 0 },
                BENCH: { tonnage: 0, reps: 0 },
                DEADLIFT: { tonnage: 0, reps: 0 }
            };
        }
        
        const ex = s.exercise.toUpperCase();
        if (weeklyData[mondayStr][ex]) {
            weeklyData[mondayStr][ex].tonnage += (s.weight * s.reps);
            weeklyData[mondayStr][ex].reps += s.reps;
        }
    });
    
    const weeksSorted = Object.keys(weeklyData).sort().reverse();
    
    if (weeksSorted.length === 0) {
        container.innerHTML = `<p class="text-gray-400 dark:text-white text-xs italic text-center py-4">No logged sets to compute weekly statistics yet.</p>`;
        return;
    }
    
    weeksSorted.forEach((weekStr, index) => {
        const weekDate = new Date(weekStr);
        const fDate = weekDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
        const data = weeklyData[weekStr];
        
        const card = document.createElement("details");
        card.className = "group bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm dark:shadow-lg transition-all duration-300";
        if (index === 0) card.setAttribute("open", "");
        
        card.innerHTML = `
            <summary class="list-none [&::-webkit-details-marker]:hidden flex items-center justify-between p-4 md:p-6 cursor-pointer select-none focus:outline-none">
                <span class="text-gray-700 dark:text-gray-200 text-xs md:text-sm font-black uppercase tracking-wider">
                    Week of ${fDate}
                </span>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-500 dark:text-gray-400 transform group-open:rotate-180 transition-transform duration-300" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                </svg>
            </summary>
            
            <div class="p-4 md:p-6 pt-0 border-t border-gray-200 dark:border-gray-700/50">
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4">
                    <!-- SQUAT -->
                    <div class="glass-card-red border-red-500/40 dark:border-red-500/30 bg-red-500/5 dark:bg-red-500/10 p-4 rounded-xl border border-l-4 border-l-red-500 flex justify-between items-center shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]">
                        <div>
                            <span class="text-xs text-gray-500 dark:text-gray-400 font-bold uppercase tracking-wider block">Squat Volume</span>
                            <span class="text-red-400 font-black text-base md:text-lg mt-0.5 block leading-none">${data.SQUAT.tonnage} ${userSettings.weightUnit.toUpperCase()}</span>
                        </div>
                        <div class="text-right">
                            <span class="text-[10px] text-gray-400 dark:text-gray-500 font-bold block uppercase tracking-wider leading-none mb-0.5">Reps</span>
                            <span class="text-green-400 font-black text-base md:text-lg block">${data.SQUAT.reps}</span>
                        </div>
                    </div>
                    <!-- BENCH -->
                    <div class="glass-card-blue border-blue-500/40 dark:border-blue-500/30 bg-blue-500/5 dark:bg-blue-500/10 p-4 rounded-xl border border-l-4 border-l-blue-500 flex justify-between items-center shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]">
                        <div>
                            <span class="text-xs text-gray-500 dark:text-gray-400 font-bold uppercase tracking-wider block">Bench Volume</span>
                            <span class="text-blue-400 font-black text-base md:text-lg mt-0.5 block leading-none">${data.BENCH.tonnage} ${userSettings.weightUnit.toUpperCase()}</span>
                        </div>
                        <div class="text-right">
                            <span class="text-[10px] text-gray-400 dark:text-gray-500 font-bold block uppercase tracking-wider leading-none mb-0.5">Reps</span>
                            <span class="text-green-400 font-black text-base md:text-lg block">${data.BENCH.reps}</span>
                        </div>
                    </div>
                    <!-- DEADLIFT -->
                    <div class="glass-card-green border-green-500/40 dark:border-green-500/30 bg-green-500/5 dark:bg-green-500/10 p-4 rounded-xl border border-l-4 border-l-green-500 flex justify-between items-center shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]">
                        <div>
                            <span class="text-xs text-gray-500 dark:text-gray-400 font-bold uppercase tracking-wider block">Deadlift Volume</span>
                            <span class="text-green-400 font-black text-base md:text-lg mt-0.5 block leading-none">${data.DEADLIFT.tonnage} ${userSettings.weightUnit.toUpperCase()}</span>
                        </div>
                        <div class="text-right">
                            <span class="text-[10px] text-gray-400 dark:text-gray-500 font-bold block uppercase tracking-wider leading-none mb-0.5">Reps</span>
                            <span class="text-green-400 font-black text-base md:text-lg block">${data.DEADLIFT.reps}</span>
                        </div>
                    </div>
                </div>
            </div>
        `;
        container.appendChild(card);
    });
}

// Render dynamic interactive Chart.js line graph offline
function renderE1RMChart(sets) {
    if (e1rmChartInstance) {
        e1rmChartInstance.destroy();
    }
    
    // Group peak e1RMs by date & exercise
    const e1rmData = {};
    sets.forEach(s => {
        if (s.set_type === "warmup" || !s.e1rm) return;
        const d = s.sessionDate;
        const ex = s.exercise.toUpperCase();
        
        if (!e1rmData[d]) {
            e1rmData[d] = { SQUAT: null, BENCH: null, DEADLIFT: null };
        }
        
        if (!e1rmData[d][ex] || s.e1rm > e1rmData[d][ex]) {
            e1rmData[d][ex] = s.e1rm;
        }
    });
    
    const datesSorted = Object.keys(e1rmData).sort();
    if (datesSorted.length === 0) {
        document.getElementById("stats-chart-card").classList.add("hidden");
        return;
    }
    document.getElementById("stats-chart-card").classList.remove("hidden");
    
    const squatPoints = [];
    const benchPoints = [];
    const deadliftPoints = [];
    
    datesSorted.forEach(d => {
        squatPoints.push(e1rmData[d].SQUAT);
        benchPoints.push(e1rmData[d].BENCH);
        deadliftPoints.push(e1rmData[d].DEADLIFT);
    });
    
    const ctx = document.getElementById("e1rmChart").getContext("2d");
    const isDark = document.documentElement.classList.contains("dark");
    const gridColor = isDark ? "rgba(255, 255, 255, 0.08)" : "rgba(0, 0, 0, 0.05)";
    const textColor = isDark ? "#9ca3af" : "#4b5563";
    
    e1rmChartInstance = new Chart(ctx, {
        type: "line",
        data: {
            labels: datesSorted,
            datasets: [
                {
                    label: "Squat",
                    data: squatPoints,
                    borderColor: "#ef4444",
                    backgroundColor: "rgba(239, 68, 68, 0.05)",
                    borderWidth: 3,
                    tension: 0.25,
                    spanGaps: true
                },
                {
                    label: "Bench Press",
                    data: benchPoints,
                    borderColor: "#3b82f6",
                    backgroundColor: "rgba(59, 130, 246, 0.05)",
                    borderWidth: 3,
                    tension: 0.25,
                    spanGaps: true
                },
                {
                    label: "Deadlift",
                    data: deadliftPoints,
                    borderColor: "#10b981",
                    backgroundColor: "rgba(16, 185, 129, 0.05)",
                    borderWidth: 3,
                    tension: 0.25,
                    spanGaps: true
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    labels: {
                        color: textColor,
                        font: { family: "Inter, system-ui, sans-serif", weight: "800", size: 10 }
                    }
                }
            },
            scales: {
                x: {
                    grid: { color: gridColor },
                    ticks: { color: textColor, font: { size: 9, weight: "bold" } }
                },
                y: {
                    grid: { color: gridColor },
                    ticks: { color: textColor, font: { size: 9, weight: "bold" } }
                }
            }
        }
    });
}

// 10. HISTORY TAB
function renderHistory() {
    const container = document.getElementById("history-sessions-container");
    container.innerHTML = "";
    
    const tx = db.transaction(["sessions", "sets"], "readonly");
    const sessionStore = tx.objectStore("sessions");
    const setStore = tx.objectStore("sets");
    
    sessionStore.getAll().onsuccess = function(e) {
        const sessions = e.target.result || [];
        if (sessions.length === 0) {
            container.innerHTML = `
                <div class="text-center py-8 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm">
                    <p class="text-gray-500 dark:text-gray-400 mb-1 text-sm font-semibold">No training history found.</p>
                    <p class="text-xs text-gray-400">Go hit the platform and log some sets on the Dashboard!</p>
                </div>
            `;
            renderE1RMChart([]);
            return;
        }
        
        // Sort sessions descending (newest first)
        sessions.sort((a,b) => b.date.localeCompare(a.date));
        
        setStore.getAll().onsuccess = function(e2) {
            const sets = e2.target.result || [];
            renderE1RMChart(sets);
            
            // Map sets to their sessionDate
            const setsMap = {};
            sets.forEach(s => {
                if (!setsMap[s.sessionDate]) {
                    setsMap[s.sessionDate] = [];
                }
                setsMap[s.sessionDate].push(s);
            });
            
            sessions.forEach((session, idx) => {
                const dateObj = new Date(session.date + "T00:00:00");
                const formattedDate = dateObj.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
                const sessionSets = setsMap[session.date] || [];
                
                const card = document.createElement("details");
                card.id = `history-card-${session.date}`;
                card.className = "group bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 border-l-4 border-l-blue-500 dark:border-l-blue-500 shadow-sm dark:shadow-lg mb-4 md:mb-6 transition-all duration-300 glass-card-blue";
                if (idx === 0) card.setAttribute("open", "");
                
                // Date sets lists layout
                let setsHtml = "";
                if (sessionSets.length === 0) {
                    setsHtml = `<p class="text-gray-500 text-xs italic py-2">No sets recorded for this session.</p>`;
                } else {
                    // Sort inside card ascending by ID
                    sessionSets.sort((a,b) => a.id - b.id);
                    sessionSets.forEach(s => {
                        const badgeClasses = {
                            warmup: "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300",
                            working: "bg-blue-50 text-blue-700 border-blue-100 dark:bg-blue-900/30 dark:text-blue-300 dark:border-blue-800",
                            failure: "bg-red-50 text-red-700 border-red-100 dark:bg-red-900/30 dark:text-red-300 dark:border-red-800"
                        }[s.set_type];
                        const rpeBadge = s.rpe ? `<span class="bg-purple-100 text-purple-800 dark:bg-purple-900/50 dark:text-purple-300 px-2 py-0.5 rounded text-[9px] font-black leading-none ml-1 uppercase">@${s.rpe}</span>` : "";
                        
                        const exerciseBoxClass = {
                            SQUAT: "glass-card-red border-red-500/30 dark:border-red-500/20 bg-red-500/5 dark:bg-red-500/10 border-l-4 border-l-red-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]",
                            BENCH: "glass-card-blue border-blue-500/30 dark:border-blue-500/20 bg-blue-500/5 dark:bg-blue-500/10 border-l-4 border-l-blue-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]",
                            DEADLIFT: "glass-card-green border-green-500/30 dark:border-green-500/20 bg-green-500/5 dark:bg-green-500/10 border-l-4 border-l-green-500 shadow-[inset_0_1px_1px_0_rgba(255,255,255,0.25)]"
                        }[s.exercise.toUpperCase()] || "bg-gray-50 dark:bg-gray-900 border-gray-200 dark:border-gray-800";

                        setsHtml += `
                            <div class="flex items-center justify-between p-3 rounded-xl border mb-2 last:mb-0 transition-all duration-300 ${exerciseBoxClass}">
                                <div>
                                    <div class="flex items-center gap-1.5">
                                        <span class="text-xs font-black ${s.exercise === 'SQUAT' ? 'text-red-500' : s.exercise === 'BENCH' ? 'text-blue-500' : 'text-green-500'} uppercase">${s.exercise}</span>
                                        <select onchange="updateSetType(${s.id}, this.value)" class="text-[9px] uppercase font-black px-1 py-0.5 rounded outline-none border-0 cursor-pointer ${badgeClasses}">
                                            <option value="warmup" ${s.set_type === 'warmup' ? 'selected' : ''}>Warm-up</option>
                                            <option value="working" ${s.set_type === 'working' ? 'selected' : ''}>Working</option>
                                            <option value="failure" ${s.set_type === 'failure' ? 'selected' : ''}>Failure</option>
                                        </select>
                                        ${rpeBadge}
                                    </div>
                                    <p class="text-xs font-black text-gray-800 dark:text-gray-100 mt-1">
                                        ${s.weight} ${userSettings.weightUnit.toUpperCase()} <span class="text-gray-400 font-bold">x</span> ${s.reps} reps
                                    </p>
                                </div>
                                <div class="flex items-center gap-3">
                                    <span class="text-[9px] font-bold text-gray-400">e1RM: ${s.e1rm}</span>
                                    <button onclick="deleteHistorySet('${session.date}', ${s.id})" class="text-gray-400 hover:text-red-500 transition-colors p-1">
                                        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                                        </svg>
                                    </button>
                                </div>
                            </div>
                        `;
                    });
                }
                
                card.innerHTML = `
                    <summary class="list-none [&::-webkit-details-marker]:hidden flex items-center justify-between p-4 md:p-6 cursor-pointer select-none focus:outline-none">
                        <div class="flex items-center gap-3">
                            <h2 class="text-lg md:text-xl font-bold text-blue-600 dark:text-blue-400">
                                ${formattedDate}
                            </h2>
                            <!-- Cascade Delete entire date card button -->
                            <button type="button" onclick="deleteHistorySession(event, '${session.date}')" class="text-gray-400 hover:text-red-500 p-1.5 transition-colors focus:outline-none" title="Delete entire Session date">
                                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                </svg>
                            </button>
                        </div>
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-500 dark:text-gray-400 transform group-open:rotate-180 transition-transform duration-300" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                             <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                        </svg>
                    </summary>
                    
                    <div class="p-4 md:p-6 pt-0 border-t border-gray-200 dark:border-gray-700/50">
                        <div class="space-y-2 mt-4">
                            ${setsHtml}
                        </div>
                    </div>
                `;
                container.appendChild(card);
            });
        };
    };
}

// Delete single set inside History
function deleteHistorySet(dateStr, setId) {
    if (!confirm("Are you sure you want to delete this logged set from your history?")) return;
    
    const tx = db.transaction("sets", "readwrite");
    const store = tx.objectStore("sets");
    store.delete(setId);
    
    tx.oncomplete = function() {
        renderHistory();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic) {
            window.webkit.messageHandlers.haptic.postMessage("medium");
        } else if (navigator.vibrate) {
            navigator.vibrate(15);
        }
    };
}

// Cascade Delete entire Workout Session date card
function deleteHistorySession(event, dateStr) {
    event.stopPropagation(); // prevent collapsing/toggling details accordion container!
    
    if (!confirm(`Are you sure you want to delete the entire session from ${dateStr}? All logged sets for this date will be permanently deleted.`)) return;
    
    // Open transaction to delete session and all corresponding sets cascade style
    const tx = db.transaction(["sessions", "sets"], "readwrite");
    const sessionStore = tx.objectStore("sessions");
    const setStore = tx.objectStore("sets");
    
    sessionStore.delete(dateStr);
    
    // Fetch and delete sets matching this sessionDate
    const index = setStore.index("sessionDate");
    index.openCursor(dateStr).onsuccess = function(e) {
        const cursor = e.target.result;
        if (cursor) {
            cursor.delete();
            cursor.continue();
        }
    };
    
    tx.oncomplete = function() {
        console.log(`Workout Session date ${dateStr} successfully cleared!`);
        const card = document.getElementById(`history-card-${dateStr}`);
        if (card) {
            card.classList.add("scale-95", "opacity-0");
            setTimeout(() => {
                renderHistory();
            }, 300);
        }
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic) {
            window.webkit.messageHandlers.haptic.postMessage("warning");
        } else if (navigator.vibrate) {
            navigator.vibrate(25);
        }
    };
}

// 11. SETTINGS TAB & UNIT CONVERSIONS (LBS / KG DETAILED MATRIX)
function renderSettings() {
    document.getElementById("set-squat").value = userSettings.squatMax;
    document.getElementById("set-bench").value = userSettings.benchMax;
    document.getElementById("set-deadlift").value = userSettings.deadliftMax;
    document.getElementById("set-bodyweight").value = userSettings.bodyWeight;
    document.getElementById("set-gender").value = userSettings.gender;
    document.getElementById("set-formula").value = userSettings.formula;
    
    // Sync checkboxes
    document.getElementById("pref-show-timer").checked = userSettings.showRestTimer;
    document.getElementById("pref-apple-health").checked = userSettings.appleHealthEnabled || false;
    document.getElementById("pref-use-grid").checked = userSettings.useGridMode || false;
    
    // Sync selectors
    syncThemeSettingsUI();
    syncUnitSettingsUI();
    setBackupFormat(currentBackupFormat);
}

function syncThemeSettingsUI() {
    const t = userSettings.theme;
    const lightBtn = document.getElementById("pref-theme-light");
    const darkBtn = document.getElementById("pref-theme-dark");
    const nightBtn = document.getElementById("pref-theme-night");
    const systemBtn = document.getElementById("pref-theme-system");
    
    const active = ["bg-blue-600", "text-white", "shadow-sm"];
    const inactive = ["text-gray-500", "dark:text-gray-400", "hover:text-gray-900", "dark:hover:text-white"];
    
    [lightBtn, darkBtn, nightBtn, systemBtn].forEach(b => {
        if (b) {
            b.classList.remove(...active);
            b.classList.add(...inactive);
        }
    });
    
    if (t === "light" && lightBtn) lightBtn.classList.add(...active);
    else if (t === "dark" && darkBtn) darkBtn.classList.add(...active);
    else if (t === "night" && nightBtn) nightBtn.classList.add(...active);
    else if (systemBtn) systemBtn.classList.add(...active);
}

function syncUnitSettingsUI() {
    const unit = userSettings.weightUnit;
    const lbsBtn = document.getElementById("pref-lbs-btn");
    const kgBtn = document.getElementById("pref-kg-btn");
    
    const active = ["bg-blue-600", "text-white", "shadow-sm"];
    const inactive = ["text-gray-500", "dark:text-gray-400", "hover:text-gray-900", "dark:hover:text-white"];
    
    [lbsBtn, kgBtn].forEach(b => {
        b.classList.remove(...active);
        b.classList.add(...inactive);
    });
    
    if (unit === "lbs") lbsBtn.classList.add(...active);
    else kgBtn.classList.add(...active);
    
    // Update local label suffixes
    document.querySelectorAll(".calc-unit-label").forEach(el => {
        el.innerText = unit.toUpperCase();
    });
}

// Toggle Rest Timer preference
function toggleRestTimerPref(checked) {
    userSettings.showRestTimer = checked;
    saveLocalSettings();
}

// Toggle Grid Mode preference
function toggleGridModePref(checked) {
    userSettings.useGridMode = checked;
    saveLocalSettings();
}

// Toggle Apple Health Settings
function toggleAppleHealthPref(enabled) {
    userSettings.appleHealthEnabled = enabled;
    saveLocalSettings();
    
    if (enabled) {
        // Trigger native iOS authorization
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.applehealth) {
            window.webkit.messageHandlers.applehealth.postMessage("requestAuthorization");
        } else {
            // Fallback if accessed via desktop browser
            alert("Apple Health integration is only available when running inside the iOS App.");
            document.getElementById("pref-apple-health").checked = false;
            userSettings.appleHealthEnabled = false;
            saveLocalSettings();
        }
    }
}

// Swift Callback Handler for Apple Health authorization success/failure
function onAppleHealthStatusChanged(status) {
    if (status === "authorized") {
        alert("Successfully connected to Apple Health!");
    } else {
        alert("Apple Health permission not granted. You can enable it anytime in iOS Settings -> Health.");
        document.getElementById("pref-apple-health").checked = false;
        userSettings.appleHealthEnabled = false;
        saveLocalSettings();
    }
}

// Switch app theme
function setAppTheme(theme) {
    userSettings.theme = theme;
    saveLocalSettings();
    syncThemeSettingsUI();
    
    const html = document.documentElement;
    let isDark = false;
    
    html.classList.remove("dark", "night");
    
    if (theme === "system") {
        if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
            html.classList.add("dark");
            isDark = true;
        }
    } else if (theme === "dark") {
        html.classList.add("dark");
        isDark = true;
    } else if (theme === "night") {
        html.classList.add("dark"); // keeps dark mode Tailwind classes active
        html.classList.add("night"); // activates specific blackout styles
        isDark = true;
    }
    
    // Native iOS Status Bar Theme Bridge
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.theme) {
        window.webkit.messageHandlers.theme.postMessage(isDark ? "dark" : "light");
    }
}

// CRITICAL USER REQUEST: Convert ALL past logs + benchmarks on unit switch!
async function toggleWeightUnitPref(targetUnit) {
    if (userSettings.weightUnit === targetUnit) return;
    
    const oldUnit = userSettings.weightUnit;
    const multiplier = targetUnit === "kg" ? 0.45359237 : (1 / 0.45359237);
    
    if (!confirm(`You are changing your primary weight unit from ${oldUnit.toUpperCase()} to ${targetUnit.toUpperCase()}.\n\nThis will physically convert and round all past logged set weights, calculated estimated 1RMs, body weight, and profile maximums to keep your training history perfectly aligned! Proceed?`)) {
        syncUnitSettingsUI();
        return;
    }
    
    // 1. Convert settings benchmarks locally
    userSettings.squatMax = Math.round(userSettings.squatMax * multiplier);
    userSettings.benchMax = Math.round(userSettings.benchMax * multiplier);
    userSettings.deadliftMax = Math.round(userSettings.deadliftMax * multiplier);
    userSettings.bodyWeight = Math.round(userSettings.bodyWeight * multiplier);
    userSettings.weightUnit = targetUnit;
    
    saveLocalSettings();
    
    // 2. Open transaction to convert database weights
    const tx = db.transaction("sets", "readwrite");
    const store = tx.objectStore("sets");
    
    store.openCursor().onsuccess = function(event) {
        const cursor = event.target.result;
        if (cursor) {
            const set = cursor.value;
            // Convert weight & e1rm
            set.weight = Math.round(set.weight * multiplier);
            set.e1rm = Math.round(set.e1rm * multiplier);
            
            cursor.update(set);
            cursor.continue();
        }
    };
    
    tx.oncomplete = function() {
        console.log("Database weight values successfully converted and rounded!");
        alert(`Successfully converted all past workout logs and lift benchmarks to ${targetUnit.toUpperCase()}!`);
        
        syncUnitSettingsUI();
        renderSettings();
        if (navigator.vibrate) navigator.vibrate(50);
    };
}

// Live-save individual profile setting changes instantly
function updateProfileSetting(field, value) {
    if (field === "squatMax" || field === "benchMax" || field === "deadliftMax") {
        userSettings[field] = parseInt(value) || 0;
        renderDashboard();
    } else if (field === "bodyWeight") {
        userSettings[field] = parseFloat(value) || 0;
    } else if (field === "formula") {
        userSettings[field] = value;
        recalculateAllDatabaseE1RMs(value);
    } else {
        userSettings[field] = value;
    }
    saveLocalSettings();
}

// Recalculates all e1RM values in the database when the formula is changed
function recalculateAllDatabaseE1RMs(formula) {
    const tx = db.transaction("sets", "readwrite");
    const store = tx.objectStore("sets");
    
    store.openCursor().onsuccess = function(event) {
        const cursor = event.target.result;
        if (cursor) {
            const set = cursor.value;
            set.e1rm = getE1RM(set.weight, set.reps, formula);
            cursor.update(set);
            cursor.continue();
        }
    };
    
    tx.oncomplete = function() {
        console.log("All database estimated 1RM values successfully updated to the new formula!");
        renderStats();
        renderHistory();
    };
}

function saveSettings(event) {
    event.preventDefault();
    
    userSettings.squatMax = parseInt(document.getElementById("set-squat").value);
    userSettings.benchMax = parseInt(document.getElementById("set-bench").value);
    userSettings.deadliftMax = parseInt(document.getElementById("set-deadlift").value);
    userSettings.bodyWeight = parseFloat(document.getElementById("set-bodyweight").value);
    userSettings.gender = document.getElementById("set-gender").value;
    userSettings.formula = document.getElementById("set-formula").value;
    
    saveLocalSettings();
    
    // Apple Health body weight sync trigger
    if (userSettings.appleHealthEnabled && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.applehealth) {
        window.webkit.messageHandlers.applehealth.postMessage({
            action: "saveWeight",
            weight: userSettings.bodyWeight,
            unit: userSettings.weightUnit
        });
    }
    
    renderStats();
    alert("Profile settings successfully saved locally!");
}

// Clear all Local App data (Reset App)
function clearAllAppStoreData() {
    if (!confirm("⚠️ DANGER ZONE! This will permanently delete all sets, custom templates, and settings. This cannot be undone. Are you absolutely sure?")) return;
    
    // Close the persistent database connection first to prevent blocking!
    if (db) {
        db.close();
    }
    
    const dbreq = indexedDB.deleteDatabase(DB_NAME);
    
    const reloadApp = () => {
        localStorage.clear();
        alert("All local data wiped successfully. The app will reload to default.");
        window.location.reload();
    };
    
    dbreq.onsuccess = reloadApp;
    dbreq.onblocked = function() {
        console.warn("Delete database blocked. Reloading to clear remaining locks.");
        reloadApp();
    };
    dbreq.onerror = function() {
        console.error("Failed to delete database.");
        reloadApp();
    };
}

let currentBackupFormat = "json";

function setBackupFormat(format) {
    currentBackupFormat = format;
    
    const jsonBtn = document.getElementById("backup-format-json");
    const csvBtn = document.getElementById("backup-format-csv");
    
    const jsonPanel = document.getElementById("backup-panel-json");
    const csvPanel = document.getElementById("backup-panel-csv");
    
    const active = ["bg-blue-600", "text-white", "shadow-sm"];
    const inactive = ["text-gray-500", "dark:text-gray-400", "hover:text-gray-900", "dark:hover:text-white"];
    
    if (format === "json") {
        jsonBtn.className = `px-3 py-1.5 rounded-md text-[10px] font-black transition uppercase ${active.join(" ")}`;
        csvBtn.className = `px-3 py-1.5 rounded-md text-[10px] font-black transition uppercase ${inactive.join(" ")}`;
        jsonPanel.classList.remove("hidden");
        csvPanel.classList.add("hidden");
    } else {
        jsonBtn.className = `px-3 py-1.5 rounded-md text-[10px] font-black transition uppercase ${inactive.join(" ")}`;
        csvBtn.className = `px-3 py-1.5 rounded-md text-[10px] font-black transition uppercase ${active.join(" ")}`;
        jsonPanel.classList.add("hidden");
        csvPanel.classList.remove("hidden");
    }
}

// 12. FILE BACKUP & RESTORE SYSTEMS (JSON Backup for phone transfers)
function exportBackupData() {
    const tx = db.transaction(["sessions", "sets", "templates"], "readonly");
    
    const backup = {
        settings: userSettings,
        sessions: [],
        sets: [],
        templates: []
    };
    
    tx.objectStore("sessions").getAll().onsuccess = function(e) {
        backup.sessions = e.target.result || [];
    };
    
    tx.objectStore("sets").getAll().onsuccess = function(e) {
        backup.sets = e.target.result || [];
    };
    
    tx.objectStore("templates").getAll().onsuccess = function(e) {
        backup.templates = e.target.result || [];
    };
    
    tx.oncomplete = function() {
        const jsonStr = JSON.stringify(backup, null, 2);
        const filename = `PersonalLift_Backup_${getTodayString()}.json`;
        
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.download) {
            window.webkit.messageHandlers.download.postMessage({
                filename: filename,
                content: jsonStr
            });
        } else {
            const blob = new Blob([jsonStr], { type: "application/json" });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            alert("Backup file successfully compiled and downloaded!");
        }
    };
}

function importBackupData(event) {
    const file = event.target.files[0];
    if (!file) return;
    
    const reader = new FileReader();
    reader.onload = function(e) {
        try {
            const backup = JSON.parse(e.target.result);
            if (!backup.settings || !backup.sets) {
                alert("Invalid backup file format. Missing core datasets.");
                return;
            }
            
            if (!confirm("This will overwrite your current settings and merge all workout logs. Do you want to proceed with the restore?")) return;
            
            // Save Settings
            userSettings = { ...DEFAULT_SETTINGS, ...backup.settings };
            saveLocalSettings();
            
            // Save database items
            const tx = db.transaction(["sessions", "sets", "templates"], "readwrite");
            
            // 1. Restore sessions
            const sessionStore = tx.objectStore("sessions");
            if (backup.sessions) {
                backup.sessions.forEach(s => sessionStore.put(s));
            }
            
            // 2. Restore sets
            const setStore = tx.objectStore("sets");
            if (backup.sets) {
                backup.sets.forEach(s => setStore.put(s));
            }
            
            // 3. Restore templates
            const templateStore = tx.objectStore("templates");
            if (backup.templates) {
                backup.templates.forEach(t => templateStore.put(t));
            }
            
            tx.oncomplete = function() {
                alert("Application databases successfully restored! The app will now refresh.");
                window.location.reload();
            };
            
        } catch(err) {
            alert("Error parsing backup JSON file. Ensure it is a valid backup.");
            console.error(err);
        }
    };
    reader.readAsText(file);
}

// 13. TEMPLATE SYSTEM IMPLEMENTATIONS
let currentTemplatesList = [];

function openTemplateLoader() {
    const modal = document.getElementById("modal-template-loader");
    const container = document.getElementById("template-loader-list");
    container.innerHTML = "";
    
    const tx = db.transaction("templates", "readonly");
    const store = tx.objectStore("templates");
    
    store.getAll().onsuccess = function(e) {
        const templates = e.target.result || [];
        currentTemplatesList = templates;
        
        if (templates.length === 0) {
            container.innerHTML = `<p class="text-gray-500 text-xs italic text-center py-4">No custom routines saved yet.</p>`;
            modal.classList.remove("hidden");
            return;
        }
        
        templates.forEach(t => {
            const card = document.createElement("div");
            card.className = "bg-gray-50 dark:bg-gray-900 p-4 rounded-xl border border-gray-200 dark:border-gray-700 flex justify-between items-center";
            card.innerHTML = `
                <div class="text-left w-3/4">
                    <h4 class="text-xs font-black text-blue-600 dark:text-blue-400 uppercase tracking-wider">${t.name}</h4>
                    <p class="text-[10px] text-gray-500 mt-1 leading-relaxed">${t.description || 'No description.'}</p>
                </div>
                <div class="flex gap-2">
                    <button onclick="loadTemplateIntoToday(${t.id})" class="bg-blue-600 hover:bg-blue-500 text-white text-[9px] font-black px-2.5 py-1.5 rounded-lg transition uppercase">Load</button>
                    <button onclick="deleteRoutineTemplate(${t.id})" class="text-gray-400 hover:text-red-500 transition-colors p-1">
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                    </button>
                </div>
            `;
            container.appendChild(card);
        });
        
        modal.classList.remove("hidden");
    };
}

function closeTemplateLoader() {
    document.getElementById("modal-template-loader").classList.add("hidden");
}

function loadTemplateIntoToday(templateId) {
    const template = currentTemplatesList.find(t => t.id === templateId);
    if (!template) return;
    
    if (!confirm(`Are you sure you want to load "${template.name}" into today's log? This will auto-create these lifts.`)) return;
    
    const todayStr = getTodayString();
    
    const tx = db.transaction(["sessions", "sets"], "readwrite");
    const sessionStore = tx.objectStore("sessions");
    const setStore = tx.objectStore("sets");
    
    sessionStore.put({ date: todayStr, notes: "" });
    
    template.exercises.forEach(te => {
        let weight = te.weight;
        // If template only has percentage, compute actual working weight
        if (!weight && te.pct) {
            const program = getWeeklyProgram(te.pct);
            weight = program[te.exercise.toLowerCase()];
        }
        
        const calculatedE1RM = getE1RM(weight, te.reps, userSettings.formula);
        
        setStore.add({
            sessionDate: todayStr,
            exercise: te.exercise.toUpperCase(),
            weight: weight || 135,
            reps: te.reps,
            set_type: te.set_type || "working",
            rpe: null,
            e1rm: calculatedE1RM
        });
    });
    
    tx.oncomplete = function() {
        closeTemplateLoader();
        renderDashboard();
        if (navigator.vibrate) navigator.vibrate(40);
    };
}

function deleteRoutineTemplate(id) {
    if (!confirm("Are you sure you want to permanently delete this routine template?")) return;
    
    const tx = db.transaction("templates", "readwrite");
    tx.objectStore("templates").delete(id);
    tx.oncomplete = () => {
        openTemplateLoader(); // reload
    };
}

function openTemplateSaver() {
    document.getElementById("modal-template-saver").classList.remove("hidden");
}

function closeTemplateSaver() {
    document.getElementById("modal-template-saver").classList.add("hidden");
}

function saveTemplateFromToday() {
    const templateName = document.getElementById("save-template-name").value.trim();
    if (!templateName) {
        alert("Please enter a name for your custom routine template.");
        return;
    }
    
    const todayStr = getTodayString();
    
    // Fetch today's sets
    const tx = db.transaction(["sets", "templates"], "readwrite");
    const setIndex = tx.objectStore("sets").index("sessionDate");
    const templateStore = tx.objectStore("templates");
    
    setIndex.getAll(todayStr).onsuccess = function(event) {
        const sets = event.target.result || [];
        if (sets.length === 0) {
            alert("No sets logged today to save into a template routine!");
            return;
        }
        
        // Sort sets by ID ascending
        sets.sort((a,b) => a.id - b.id);
        
        const exercises = sets.map(s => ({
            exercise: s.exercise,
            weight: s.weight,
            reps: s.reps,
            set_type: s.set_type
        }));
        
        const newTemplate = {
            name: templateName,
            description: `Saved from workout logged on ${todayStr}`,
            exercises: exercises
        };
        
        templateStore.add(newTemplate);
    };
    
    tx.oncomplete = function() {
        closeTemplateSaver();
        document.getElementById("save-template-name").value = "";
        alert(`Successfully saved routine template "${templateName}"!`);
        if (navigator.vibrate) navigator.vibrate(30);
    };
}

// 14. CSV IMPORT & EXPORT HANDLERS (Client-Side HTML5 APIs)
function escapeCSV(val) {
    if (val === undefined || val === null) return "";
    let str = String(val);
    if (str.includes(",") || str.includes('"') || str.includes("\n") || str.includes("\r")) {
        return '"' + str.replace(/"/g, '""') + '"';
    }
    return str;
}

function exportCSV() {
    const tx = db.transaction(["sets", "sessions"], "readonly");
    const setsStore = tx.objectStore("sets");
    const sessionsStore = tx.objectStore("sessions");
    
    sessionsStore.getAll().onsuccess = function(e) {
        const sessions = e.target.result || [];
        const sessionsMap = {};
        sessions.forEach(s => {
            sessionsMap[s.date] = s.notes || "";
        });
        
        setsStore.getAll().onsuccess = function(event) {
            const sets = event.target.result || [];
            if (sets.length === 0) {
                alert("No logged workout history available to export.");
                return;
            }
            
            // Sort sets by date descending
            sets.sort((a,b) => b.sessionDate.localeCompare(a.sessionDate));
            
            // Build CSV columns with all possible data to match JSON backup
            let csvContent = "Date,Exercise,Weight,Reps,Set Type,RPE,Estimated 1RM,Session Notes,Squat Max,Bench Max,Deadlift Max,Body Weight,Gender,Formula,Weight Unit,Show Rest Timer,Theme\n";
            
            sets.forEach(s => {
                const rpeStr = s.rpe !== null && s.rpe !== undefined ? s.rpe : "";
                const notesVal = sessionsMap[s.sessionDate] || "";
                
                const squatMax = userSettings.squatMax || "";
                const benchMax = userSettings.benchMax || "";
                const deadliftMax = userSettings.deadliftMax || "";
                const bodyWeight = userSettings.bodyWeight || "";
                const gender = userSettings.gender || "";
                const formula = userSettings.formula || "";
                const weightUnit = userSettings.weightUnit || "";
                const showRestTimer = userSettings.showRestTimer !== undefined ? userSettings.showRestTimer : "";
                const theme = userSettings.theme || "";
                
                csvContent += `${s.sessionDate},${escapeCSV(s.exercise)},${s.weight},${s.reps},${escapeCSV(s.set_type)},${rpeStr},${s.e1rm},${escapeCSV(notesVal)},${squatMax},${benchMax},${deadliftMax},${bodyWeight},${escapeCSV(gender)},${escapeCSV(formula)},${escapeCSV(weightUnit)},${showRestTimer},${escapeCSV(theme)}\n`;
            });
            
            const filename = `PersonalLift_History_${getTodayString()}.csv`;
            
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.download) {
                window.webkit.messageHandlers.download.postMessage({
                    filename: filename,
                    content: csvContent
                });
            } else {
                const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
                const url = URL.createObjectURL(blob);
                const a = document.createElement("a");
                a.href = url;
                a.download = filename;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
                alert("Lifting history exported successfully as CSV!");
            }
        };
    };
}

function importCSV(event) {
    const file = event.target.files[0];
    if (!file) return;
    
    const reader = new FileReader();
    reader.onload = function(e) {
        const text = e.target.result;
        // Split by lines, supporting both standard LF (\n) and CR+LF (\r\n)
        const lines = text.split(/\r?\n/);
        if (lines.length <= 1) {
            alert("CSV file appears to be empty.");
            event.target.value = "";
            return;
        }
        
        if (!confirm("This will merge CSV entries into your local device database. Proceed?")) {
            event.target.value = "";
            return;
        }
        
        const tx = db.transaction(["sessions", "sets"], "readwrite");
        const sessionStore = tx.objectStore("sessions");
        const setStore = tx.objectStore("sets");
        
        let importCount = 0;
        
        // CSV parser loop
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;
            
            // Auto-detect delimiter (comma vs semicolon)
            let delimiter = ",";
            if (line.includes(";") && !line.includes(",")) {
                delimiter = ";";
            } else if (line.includes(";")) {
                const commas = (line.match(/,/g) || []).length;
                const semicolons = (line.match(/;/g) || []).length;
                if (semicolons > commas) {
                    delimiter = ";";
                }
            }
            
            // Robust CSV parser line splitter that handles double quotes with embedded commas/newlines
            const cols = [];
            let inQuotes = false;
            let currentField = "";
            for (let charIndex = 0; charIndex < line.length; charIndex++) {
                const char = line[charIndex];
                if (char === '"') {
                    if (inQuotes && line[charIndex + 1] === '"') {
                        currentField += '"';
                        charIndex++; // skip next quote
                    } else {
                        inQuotes = !inQuotes;
                    }
                } else if (char === delimiter && !inQuotes) {
                    cols.push(currentField.trim());
                    currentField = "";
                } else {
                    currentField += char;
                }
            }
            cols.push(currentField.trim());
            
            if (cols.length < 4) continue;
            
            const dateStr = cols[0];
            const exercise = cols[1].toUpperCase();
            const weight = parseInt(cols[2]);
            const reps = parseInt(cols[3]);
            
            // Set type, fallback to "working"
            let setType = "working";
            if (cols[4]) {
                const sType = cols[4].toLowerCase();
                if (sType.includes("warm") || sType.includes("warmup") || sType.includes("warm-up")) {
                    setType = "warmup";
                } else if (sType.includes("fail") || sType.includes("failure") || sType.includes("amrap")) {
                    setType = "failure";
                }
            }
            
            // RPE clean parsing
            let rpe = null;
            if (cols[5]) {
                const cleanRpe = cols[5].replace("@", "").trim();
                if (cleanRpe && !isNaN(cleanRpe)) {
                    rpe = parseFloat(cleanRpe);
                }
            }
            
            // Validate columns
            if (!dateStr || !exercise || isNaN(weight) || isNaN(reps)) {
                console.warn(`Skipping invalid CSV line ${i + 1}: ${line}`);
                continue;
            }
            
            if (exercise !== "SQUAT" && exercise !== "BENCH" && exercise !== "DEADLIFT") {
                console.warn(`Skipping invalid exercise ${exercise} at line ${i + 1}`);
                continue;
            }
            
            // Session notes parsing
            const sessionNotes = cols[7] || "";
            
            // Ensure session exists in IndexedDB and restore notes if present
            sessionStore.put({ date: dateStr, notes: sessionNotes });
            
            const calculatedE1RM = getE1RM(weight, reps, userSettings.formula);
            
            // Add logged set
            setStore.add({
                sessionDate: dateStr,
                exercise: exercise,
                weight: weight,
                reps: reps,
                set_type: setType,
                rpe: rpe,
                e1rm: calculatedE1RM
            });
            
            // If settings columns exist, restore them from the first record
            if (i === 1) {
                if (cols[8]) userSettings.squatMax = parseInt(cols[8]) || userSettings.squatMax;
                if (cols[9]) userSettings.benchMax = parseInt(cols[9]) || userSettings.benchMax;
                if (cols[10]) userSettings.deadliftMax = parseInt(cols[10]) || userSettings.deadliftMax;
                if (cols[11]) userSettings.bodyWeight = parseInt(cols[11]) || userSettings.bodyWeight;
                if (cols[12]) userSettings.gender = cols[12] || userSettings.gender;
                if (cols[13]) userSettings.formula = cols[13] || userSettings.formula;
                if (cols[14]) userSettings.weightUnit = cols[14] || userSettings.weightUnit;
                if (cols[15]) userSettings.showRestTimer = cols[15] === "true" ? true : (cols[15] === "false" ? false : userSettings.showRestTimer);
                if (cols[16]) userSettings.theme = cols[16] || userSettings.theme;
                saveLocalSettings();
            }
            
            importCount++;
        }
        
        tx.oncomplete = function() {
            syncThemeSettingsUI();
            syncUnitSettingsUI();
            
            alert(`Successfully imported ${importCount} sets of CSV history data!`);
            event.target.value = ""; // Reset input file element
            
            // Reload and navigate to history tab
            if (activeTab === "history") {
                renderHistory();
            } else {
                switchTab("history");
            }
        };
        
        tx.onerror = function(err) {
            console.error("CSV Import transaction failed:", err);
            alert("An error occurred during import. Some rows may not have been saved.");
            event.target.value = "";
        };
    };
    reader.readAsText(file);
}

// 16. INTERACTIVE WIZARD ONBOARDING
let currentOnboardSlide = 0;

function setOnboardingGender(gender) {
    document.getElementById("onboard-gender").value = gender;
    
    // Reset genders styling
    const maleBtn = document.getElementById("gender-male-btn");
    const femaleBtn = document.getElementById("gender-female-btn");
    const nbBtn = document.getElementById("gender-nb-btn");
    const otherBtn = document.getElementById("gender-other-btn");
    
    maleBtn.className = "bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer";
    femaleBtn.className = "bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer";
    nbBtn.className = "bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer";
    otherBtn.className = "bg-white/5 hover:bg-white/10 border border-white/10 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer";
    
    // Highlight active one
    if (gender === "male") {
        maleBtn.className = "bg-white/15 border-2 border-purple-500/60 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer shadow-sm";
    } else if (gender === "female") {
        femaleBtn.className = "bg-white/15 border-2 border-purple-500/60 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer shadow-sm";
    } else if (gender === "non_binary") {
        nbBtn.className = "bg-white/15 border-2 border-purple-500/60 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer shadow-sm";
    } else {
        otherBtn.className = "bg-white/15 border-2 border-purple-500/60 rounded-xl py-3 text-xs font-black text-white transition uppercase text-center cursor-pointer shadow-sm";
    }
}
window.setOnboardingGender = setOnboardingGender;

function updateOnboardingDots() {
    const dotsContainer = document.getElementById("onboarding-progress-dots");
    if (!dotsContainer) return;
    
    // 5 dots (Slides 1 to 5)
    dotsContainer.innerHTML = "";
    for (let i = 1; i <= 5; i++) {
        const dot = document.createElement("div");
        if (i <= currentOnboardSlide) {
            // Completed or active steps
            dot.className = "w-2.5 h-1.5 rounded-full bg-blue-600 transition-all duration-300";
        } else {
            // Unvisited steps
            dot.className = "w-1.5 h-1.5 rounded-full bg-gray-800 transition-all duration-300";
        }
        dotsContainer.appendChild(dot);
    }
}

function nextOnboardingSlide() {
    if (currentOnboardSlide < 5) {
        // Hide current
        const curSlideEl = document.getElementById(`onboard-slide-${currentOnboardSlide}`);
        if (curSlideEl) curSlideEl.classList.add("hidden");
        
        currentOnboardSlide++;
        
        // Show next
        const nextSlideEl = document.getElementById(`onboard-slide-${currentOnboardSlide}`);
        if (nextSlideEl) nextSlideEl.classList.remove("hidden");
        
        // Update back button visibility
        const backBtn = document.getElementById("onboard-back-btn");
        if (currentOnboardSlide > 0 && currentOnboardSlide < 5) {
            backBtn.classList.remove("hidden");
        } else {
            backBtn.classList.add("hidden");
        }
        
        // Update next button text
        const nextBtn = document.getElementById("onboard-next-btn");
        if (currentOnboardSlide === 0) {
            nextBtn.innerText = "Get Started";
        } else if (currentOnboardSlide < 5) {
            nextBtn.innerText = "Next Step";
        } else {
            nextBtn.innerText = "Enter App";
        }
        
        updateOnboardingDots();
    } else {
        // Complete Onboarding!
        const squatVal = parseInt(document.getElementById("onboard-squat").value) || 315;
        const benchVal = parseInt(document.getElementById("onboard-bench").value) || 225;
        const deadliftVal = parseInt(document.getElementById("onboard-deadlift").value) || 405;
        const weightVal = parseFloat(document.getElementById("onboard-bodyweight").value) || 180;
        const genderVal = document.getElementById("onboard-gender").value || "other";
        
        // Apply to settings
        userSettings.squatMax = squatVal;
        userSettings.benchMax = benchVal;
        userSettings.deadliftMax = deadliftVal;
        userSettings.bodyWeight = weightVal;
        userSettings.gender = genderVal;
        saveLocalSettings();
        
        // Save onboarded flag
        localStorage.setItem("privatelift_onboarded", "true");
        
        // Populate inputs in settings page
        document.getElementById("set-squat").value = squatVal;
        document.getElementById("set-bench").value = benchVal;
        document.getElementById("set-deadlift").value = deadliftVal;
        document.getElementById("set-bodyweight").value = weightVal;
        document.getElementById("set-gender").value = genderVal;
        
        // Re-render dashboard intensities & stats
        updateIntensity(currentIntensity);
        renderStats();
        
        // Close overlay with a sleek fade-out scale transition
        const overlay = document.getElementById("onboarding-overlay");
        if (overlay) {
            overlay.classList.remove("opacity-100");
            overlay.classList.add("opacity-0");
            const container = overlay.querySelector("div");
            if (container) {
                container.classList.remove("scale-100");
                container.classList.add("scale-95");
            }
            setTimeout(() => {
                overlay.classList.add("hidden");
            }, 500);
        }
    }
}
window.nextOnboardingSlide = nextOnboardingSlide;

function prevOnboardingSlide() {
    if (currentOnboardSlide > 0) {
        // Hide current
        const curSlideEl = document.getElementById(`onboard-slide-${currentOnboardSlide}`);
        if (curSlideEl) curSlideEl.classList.add("hidden");
        
        currentOnboardSlide--;
        
        // Show previous
        const prevSlideEl = document.getElementById(`onboard-slide-${currentOnboardSlide}`);
        if (prevSlideEl) prevSlideEl.classList.remove("hidden");
        
        // Update buttons
        const backBtn = document.getElementById("onboard-back-btn");
        if (currentOnboardSlide > 0 && currentOnboardSlide < 5) {
            backBtn.classList.remove("hidden");
        } else {
            backBtn.classList.add("hidden");
        }
        
        const nextBtn = document.getElementById("onboard-next-btn");
        if (currentOnboardSlide === 0) {
            nextBtn.innerText = "Get Started";
        } else {
            nextBtn.innerText = "Next Step";
        }
        
        updateOnboardingDots();
    }
}
window.prevOnboardingSlide = prevOnboardingSlide;

function checkOnboardingCheck() {
    const onboarded = localStorage.getItem("privatelift_onboarded");
    if (!onboarded) {
        const overlay = document.getElementById("onboarding-overlay");
        if (overlay) {
            overlay.classList.remove("hidden");
            // Force a reflow
            void overlay.offsetWidth;
            overlay.classList.remove("opacity-0");
            overlay.classList.add("opacity-100");
            const container = overlay.querySelector("div");
            if (container) {
                container.classList.remove("scale-95");
                container.classList.add("scale-100");
            }
        }
    }
}
window.checkOnboardingCheck = checkOnboardingCheck;

// 15. INITIALIZATION WAKE HOOKS
function initWakeHooks() {
    initDB().then(() => {
        // 2. Load preferences
        loadLocalSettings();
        
        // 3. Set standard color themes based on preferences
        setAppTheme(userSettings.theme);
        
        // Initialize intensity slider to last persisted value
        const intensitySlider = document.getElementById("intensity-slider");
        if (intensitySlider) {
            intensitySlider.value = currentIntensity;
        }
        updateIntensity(currentIntensity);
        
        // Resume any pending rest timers from local storage
        checkTimerResume();
        
        // 4. Load initial tab screen
        switchTab("dashboard");
        
        // Calibrate onboarding check for first-time use
        checkOnboardingCheck();
        
        // Request durable storage to prevent OS eviction
        if (navigator.storage && navigator.storage.persist) {
            navigator.storage.persist().then(persisted => {
                if (persisted) {
                    console.log(" DURATION STORAGE OPTION: Active. Apple storage persistence fully secured.");
                }
            });
        }
    }).catch(err => {
        console.error("Wake hooks initialization failed:", err);
    });
}

// Instantaneous readyState check to resolve WKWebView timing bugs
if (document.readyState === "complete" || document.readyState === "interactive") {
    initWakeHooks();
} else {
    document.addEventListener("DOMContentLoaded", initWakeHooks);
}
