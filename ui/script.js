let currentAudio = null;
let currentStationIndex = 0;
let stationsList = [];
let autoHideTimer = null;

const radioContainer = document.getElementById('radio-container');
const activeStationName = document.getElementById('active-station-name');
const activeStationLogo = document.getElementById('active-station-logo');
const stationsWrapper = document.getElementById('stations-wrapper');

function closeUI() {
    if (autoHideTimer) {
        clearTimeout(autoHideTimer);
        autoHideTimer = null;
    }
    radioContainer.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8'
        },
        body: JSON.stringify({})
    });
}

function generateStations(stations) {
    stationsWrapper.innerHTML = '';
    stationsList = stations;
    
    stations.forEach((station, index) => {
        const circle = document.createElement('div');
        circle.className = 'station-circle';
        circle.setAttribute('data-index', index);
        circle.setAttribute('data-type', station.type);
        
        if (station.image && station.image !== "") {
            const img = document.createElement('img');
            img.src = getLogoSrc(station.image);
            img.alt = station.name;
            img.onerror = function() {
                img.style.display = 'none';
                circle.innerText = station.icon;
            };
            circle.appendChild(img);
        } else {
            circle.innerText = station.icon;
        }
        
        if (index === currentStationIndex) {
            circle.classList.add('active');
            activeStationName.innerText = station.name;
            updateActiveNameGradient(station.type);
            updateHeaderLogo(station.image);
            updateVisualizer(station.type);
        }
        
        circle.addEventListener('click', () => {
            selectStation(index);
        });
        
        stationsWrapper.appendChild(circle);
    });

    updateSlider();
}

function updateSlider() {
    if (!stationsWrapper) return;
    const shift = (currentStationIndex * 80) + 32;
    stationsWrapper.style.transform = `translateX(-${shift}px)`;
}

function updateActiveNameGradient(type) {
    if (type === 'off') {
        activeStationName.style.background = 'linear-gradient(90deg, #ff453a, #ff3b30)';
    } else {
        activeStationName.style.background = 'linear-gradient(90deg, #00f2fe, #4facfe)';
    }
    activeStationName.style.webkitBackgroundClip = 'text';
    activeStationName.style.webkitTextFillColor = 'transparent';
}

function getLogoSrc(imageName) {
    if (!imageName) return '';
    if (imageName.startsWith('http://') || imageName.startsWith('https://')) {
        return imageName;
    }
    return `images/${imageName}`;
}

function updateHeaderLogo(imageName) {
    if (imageName && imageName !== "") {
        activeStationLogo.src = getLogoSrc(imageName);
        activeStationLogo.classList.remove('hidden');
        activeStationLogo.onerror = function() {
            activeStationLogo.classList.add('hidden');
        };
    } else {
        activeStationLogo.classList.add('hidden');
    }
}

function updateVisualizer(type) {
    const visualizer = document.getElementById('audio-visualizer');
    if (visualizer) {
        if (type === 'off') {
            visualizer.classList.remove('active');
        } else {
            visualizer.classList.add('active');
        }
    }
}

function selectStation(index) {
    if (stationsList.length === 0) return;
    if (index < 0 || index >= stationsList.length) return;
    
    const station = stationsList[index];
    if (!station) return;
    
    if (autoHideTimer) {
        clearTimeout(autoHideTimer);
        autoHideTimer = setTimeout(() => {
            closeUI();
        }, 1500);
    }
    
    const items = document.querySelectorAll('.station-circle');
    items.forEach(item => item.classList.remove('active'));
    
    const activeItem = document.querySelector(`.station-circle[data-index="${index}"]`);
    if (activeItem) activeItem.classList.add('active');
    
    currentStationIndex = index;
    activeStationName.innerText = station.name;
    updateActiveNameGradient(station.type);
    updateHeaderLogo(station.image);
    updateVisualizer(station.type);

    if (currentAudio) {
        currentAudio.pause();
        currentAudio.src = '';
        currentAudio = null;
    }
    
    fetch(`https://${GetParentResourceName()}/selectStation`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8'
        },
        body: JSON.stringify({
            index: index,
            name: station.name,
            image: station.image,
            type: station.type,
            value: station.value
        })
    });

    updateSlider();
}

window.addEventListener('message', function(event) {
    const data = event.data;
    const radioCard = document.querySelector('.radio-card');
    
    if (data.action === 'open') {
        if (autoHideTimer) {
            clearTimeout(autoHideTimer);
            autoHideTimer = null;
        }
        if (radioCard) radioCard.classList.remove('mini');
        radioContainer.classList.remove('hidden');
        generateStations(data.stations);
    } else if (data.action === 'close') {
        if (autoHideTimer) {
            clearTimeout(autoHideTimer);
            autoHideTimer = null;
        }
        radioContainer.classList.add('hidden');
    } else if (data.action === 'nextStation') {
        let nextIndex = (currentStationIndex + 1) % stationsList.length;
        selectStation(nextIndex);
    } else if (data.action === 'prevStation') {
        let prevIndex = (currentStationIndex - 1 + stationsList.length) % stationsList.length;
        selectStation(prevIndex);
    } else if (data.action === 'cycleNext') {
        if (autoHideTimer) {
            clearTimeout(autoHideTimer);
        }
        
        if (radioCard) radioCard.classList.add('mini');
        radioContainer.classList.remove('hidden');
        
        if (stationsList.length === 0 && data.stations) {
            generateStations(data.stations);
        }
        
        if (stationsList.length > 0) {
            let nextIndex = (currentStationIndex + 1) % stationsList.length;
            selectStation(nextIndex);
        }
        
        autoHideTimer = setTimeout(() => {
            closeUI();
        }, 1500);
    } else if (data.action === 'syncVisuals') {
        if (autoHideTimer) {
            clearTimeout(autoHideTimer);
            autoHideTimer = null;
        }

        if (stationsList.length === 0 && data.stations) {
            generateStations(data.stations);
        }

        if (data.showUI) {
            if (radioCard) radioCard.classList.add('mini');
            radioContainer.classList.remove('hidden');
            
            autoHideTimer = setTimeout(() => {
                closeUI();
            }, 1500);
        }

        currentStationIndex = data.index;
        activeStationName.innerText = data.name;
        updateActiveNameGradient(data.type);
        updateHeaderLogo(data.image);
        updateVisualizer(data.type);
        
        const items = document.querySelectorAll('.station-circle');
        items.forEach(item => item.classList.remove('active'));
        
        const activeItem = document.querySelector(`.station-circle[data-index="${data.index}"]`);
        if (activeItem) activeItem.classList.add('active');
        
        updateSlider();
    } else if (data.action === 'playStream') {
        if (currentAudio) {
            currentAudio.pause();
            currentAudio.src = '';
            currentAudio = null;
        }
        
        currentAudio = new Audio(data.url);
        currentAudio.volume = 0.35;
        
        currentAudio.addEventListener('error', (e) => {
            activeStationName.innerText = "Chyba streamu";
            console.error("Failed to load stream:", e);
        });
        
        currentAudio.play().catch(err => {
            console.error("Audio playback error:", err);
        });
    } else if (data.action === 'stopStream') {
        if (currentAudio) {
            currentAudio.pause();
            currentAudio.src = '';
            currentAudio = null;
        }
    } else if (data.action === 'stopAll') {
        if (currentAudio) {
            currentAudio.pause();
            currentAudio.src = '';
            currentAudio = null;
        }
        if (autoHideTimer) {
            clearTimeout(autoHideTimer);
            autoHideTimer = null;
        }
        currentStationIndex = 0;
        activeStationName.innerText = "Vypnuto";
        updateActiveNameGradient('off');
        updateHeaderLogo(null);
        updateVisualizer('off');
        
        const items = document.querySelectorAll('.station-circle');
        items.forEach(item => {
            item.classList.remove('active');
            if (item.getAttribute('data-type') === 'off') {
                item.classList.add('active');
            }
        });
        updateSlider();
    }
});

window.addEventListener('keyup', function(event) {
    if (event.key === 'Escape') {
        closeUI();
    }
});
