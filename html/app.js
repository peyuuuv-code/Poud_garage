const app = document.getElementById('app');
const title = document.getElementById('title');
const eyebrow = document.getElementById('eyebrow');
const closeButton = document.getElementById('close');
const vehiclesElement = document.getElementById('vehicles');
const emptyElement = document.getElementById('empty');
const promptElement = document.getElementById('prompt');
const promptKey = document.getElementById('promptKey');
const promptTitle = document.getElementById('promptTitle');
const promptDescription = document.getElementById('promptDescription');

let currentGarageId = null;
let text = {};

function post(name, data = {}) {
    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'Poud_garage';

    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8'
        },
        body: JSON.stringify(data)
    });
}

function ready() {
    post('ready').catch(() => {});
}

function closeUi() {
    app.classList.add('hidden');
    currentGarageId = null;
    post('close');
}

function renderVehicles(vehicles) {
    vehiclesElement.innerHTML = '';

    if (!vehicles || vehicles.length < 1) {
        emptyElement.textContent = text.noVehicles || 'Zadne vozidlo.';
        emptyElement.classList.remove('hidden');
        return;
    }

    emptyElement.classList.add('hidden');

    vehicles.forEach((vehicle) => {
        const row = document.createElement('article');
        row.className = `vehicle ${vehicle.stored ? '' : 'is-out'}`;

        const info = document.createElement('div');

        const name = document.createElement('p');
        name.className = 'vehicle-name';
        name.textContent = vehicle.label || vehicle.model || 'Vozidlo';

        const meta = document.createElement('div');
        meta.className = 'vehicle-meta';

        const plate = document.createElement('span');
        plate.textContent = `${text.plate || 'SPZ'}: ${vehicle.plate || '-'}`;

        const status = document.createElement('span');
        status.className = 'status';
        status.textContent = vehicle.stored ? (text.stored || 'V garazi') : (text.out || 'Venku');

        meta.appendChild(plate);
        meta.appendChild(status);
        info.appendChild(name);
        info.appendChild(meta);

        const button = document.createElement('button');
        button.className = 'take-out';
        button.type = 'button';
        button.disabled = !vehicle.stored;
        button.textContent = vehicle.stored ? 'Vyjet' : 'Venku';
        button.addEventListener('click', () => {
            post('takeOut', {
                garageId: currentGarageId,
                plate: vehicle.plate
            });
        });

        row.appendChild(info);
        row.appendChild(button);
        vehiclesElement.appendChild(row);
    });
}

function setGarageData(data) {
    text = data.text || text || {};

    if (data.garage) {
        currentGarageId = data.garage.id;
        title.textContent = data.garage.label || 'Garage';
    }

    eyebrow.textContent = text.garageTitle || 'GARAZ';

    if (data.loading) {
        vehiclesElement.innerHTML = '';
        emptyElement.textContent = text.loadingVehicles || 'Nacitam vozidla...';
        emptyElement.classList.remove('hidden');
        return;
    }

    renderVehicles(data.vehicles || []);
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'close') {
        app.classList.add('hidden');
        currentGarageId = null;
        return;
    }

    if (data.action === 'showPrompt') {
        promptKey.textContent = data.key || 'E';
        promptTitle.textContent = data.title || 'Zaparkovat vozidlo';
        promptDescription.textContent = data.description || 'Stiskni E pro predani auta obsluze.';
        promptElement.classList.remove('hidden');
        return;
    }

    if (data.action === 'hidePrompt') {
        promptElement.classList.add('hidden');
        return;
    }

    if (data.action !== 'open') return;

    setGarageData(data);
    app.classList.remove('hidden');
});

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'updateVehicles') {
        setGarageData(data);
        app.classList.remove('hidden');
    }
});

closeButton.addEventListener('click', closeUi);

document.addEventListener('keyup', (event) => {
    if (event.key === 'Escape') {
        closeUi();
    }
});

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', ready);
} else {
    ready();
}
