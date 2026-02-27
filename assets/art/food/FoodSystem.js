/**
 * 🍖 FoodSystem.js
 * 
 * Handles food consumption for healing and buffs
 * - Right-click to eat food items
 * - Different foods have different effects (HP, stamina, speed, etc.)
 * - Buffs stack and last 30 seconds each
 * - Works for both player and companion
 */

export class FoodSystem {
    constructor(voxelWorld) {
        this.voxelWorld = voxelWorld;
        
        // Active buffs (can stack multiple of same type)
        this.activeBuffs = [];
        
        // Food properties: { healing, stamina, buff, buffDuration }
        // Synced with KitchenBenchSystem.js foodDatabase
        this.foodData = {
            // 🍞 BASIC COOKED FOODS
            'roasted_wheat': {
                name: '🍞 Bread',
                healing: 0,
                stamina: 30,
                buff: null
            },
            'baked_potato': {
                name: '🥔 Baked Potato',
                healing: 0,
                stamina: 45,
                buff: { type: 'stamina_drain_reduction', amount: 0.2 } // -20% drain
            },
            'roasted_corn': {
                name: '🌽 Roasted Corn',
                healing: 0,
                stamina: 25,
                buff: null
            },
            'grilled_fish': {
                name: '🍣 Grilled Fish',
                healing: 0,
                stamina: 75,
                buff: { type: 'speed', amount: 0.2 } // +20% speed
            },
            
            // 🥗 COMBINATIONS (2 ingredients)
            'carrot_stew': {
                name: '🥕🍲 Carrot Stew',
                healing: 0,
                stamina: 60,
                buff: { type: 'speed', amount: 0.15 } // +15% speed
            },
            'berry_bread': {
                name: '🍓🍞 Berry Bread',
                healing: 0,
                stamina: 50,
                buff: { type: 'stamina_regen', amount: 1.0 } // 2x regen (100% bonus)
            },
            'mushroom_soup': {
                name: '🍄🍲 Mushroom Soup',
                healing: 0,
                stamina: 55,
                buff: { type: 'speed', amount: 0.25 } // +25% speed
            },
            'fish_rice': {
                name: '🐟🍚 Fish & Rice',
                healing: 0,
                stamina: 100,
                buff: { type: 'stamina_drain_reduction', amount: 0.3 } // -30% drain
            },
            
            // 🍰 ADVANCED (3+ ingredients)
            'veggie_medley': {
                name: '🥗 Veggie Medley',
                healing: 0,
                stamina: 80,
                buff: { type: 'speed', amount: 0.3 } // +30% speed
            },
            'honey_bread': {
                name: '🍯� Honey Bread',
                healing: 4,        // 2 hearts!
                stamina: 70,
                buff: { type: 'stamina_regen', amount: 2.0 } // 3x regen (200% bonus)
            },
            'pumpkin_pie': {
                name: '🎃🥧 Pumpkin Pie',
                healing: 0,
                stamina: 120,
                buff: { type: 'speed', amount: 0.2 } // +20% speed
            },
            'super_stew': {
                name: '🍲 Super Stew',
                healing: 6,        // 3 hearts!!!
                stamina: 150,
                buff: { type: 'speed', amount: 0.4 } // +40% speed - LEGENDARY!
            },
            
            // 🍪 QUICK SNACKS
            'berry_honey_snack': {
                name: '🍓🍯 Berry-Honey Snack',
                healing: 0,
                stamina: 40,
                buff: { type: 'stamina_regen', amount: 3.0 } // 4x regen (300% bonus)
            },
            'energy_bar': {
                name: '⚡ Energy Bar',
                healing: 0,
                stamina: 60,
                buff: { type: 'speed', amount: 0.5 } // +50% speed!!!
            },
            
            // Raw foods (less effective)
            'berry': {
                name: '🍓 Berry',
                healing: 0,
                stamina: 10,
                buff: null
            },
            'apple': {
                name: '🍎 Apple',
                healing: 1,        // Half heart
                stamina: 12,
                buff: null
            },
            'wheat': {
                name: '🌾 Wheat',
                healing: 0,
                stamina: 5,
                buff: null
            },
            'rice': {
                name: '🍚 Rice',
                healing: 0,
                stamina: 5,
                buff: null
            },
            'corn_ear': {
                name: '🌽 Corn',
                healing: 0,
                stamina: 8,
                buff: null
            },
            'carrot': {
                name: '🥕 Carrot',
                healing: 1,        // Half heart
                stamina: 8,
                buff: null
            },
            'potato': {
                name: '🥔 Potato',
                healing: 1,        // Half heart
                stamina: 8,
                buff: null
            },
            'pumpkin': {
                name: '🎃 Pumpkin',
                healing: 2,        // 1 heart
                stamina: 15,
                buff: null
            },
            'fish': {
                name: '🐟 Fish',
                healing: 1,        // Half heart
                stamina: 10,
                buff: null
            },
            'mushroom': {
                name: '🍄 Mushroom',
                healing: 0,
                stamina: 5,
                buff: null
            },
            'honey': {
                name: '🍯 Honey',
                healing: 2,        // 1 heart
                stamina: 20,
                buff: null
            },
            'egg': {
                name: '🥚 Egg',
                healing: 1,        // Half heart
                stamina: 10,
                buff: null
            }
        };
        
        console.log('🍖 FoodSystem initialized');
    }
    
    /**
     * Check if an item is food
     */
    isFood(itemType) {
        // Remove 'crafted_' prefix if present
        const baseType = itemType.replace('crafted_', '');
        return this.foodData.hasOwnProperty(baseType);
    }
    
    /**
     * Eat food (player only)
     * Returns true if food was consumed
     */
    eatFood(itemType) {
        // Remove 'crafted_' prefix
        const baseType = itemType.replace('crafted_', '');
        const food = this.foodData[baseType];
        
        if (!food) {
            console.log(`❌ ${itemType} is not edible`);
            return false;
        }
        
        console.log(`🍖 Eating ${food.name}...`);
        
        let effectsApplied = [];
        
        // 💚 Apply healing
        if (food.healing > 0 && this.voxelWorld.playerHP) {
            if (this.voxelWorld.playerHP.currentHP < this.voxelWorld.playerHP.maxHP) {
                // Smart healing: prioritize completing broken hearts
                const isOddHP = (this.voxelWorld.playerHP.currentHP % 2) === 1;
                let healAmount = food.healing;
                
                // If has broken heart and healing amount is even, reduce by 1 to complete the heart first
                if (isOddHP && healAmount % 2 === 0) {
                    this.voxelWorld.playerHP.heal(1);
                    healAmount -= 1;
                    effectsApplied.push('💔→❤️');
                }
                
                // Apply remaining healing
                if (healAmount > 0) {
                    this.voxelWorld.playerHP.heal(healAmount);
                    const hearts = Math.floor(healAmount / 2);
                    const halfHeart = healAmount % 2;
                    if (hearts > 0) effectsApplied.push(`+${hearts}❤️`);
                    if (halfHeart > 0) effectsApplied.push(`+💔`);
                }
            } else {
                effectsApplied.push('Already at full HP');
            }
        }
        
        // ⚡ Apply stamina
        if (food.stamina > 0 && this.voxelWorld.staminaSystem) {
            this.voxelWorld.staminaSystem.currentStamina = Math.min(
                this.voxelWorld.staminaSystem.maxStamina,
                this.voxelWorld.staminaSystem.currentStamina + food.stamina
            );
            effectsApplied.push(`+${food.stamina} stamina`);
        }
        
        // 🌟 Apply buff
        if (food.buff) {
            this.addBuff(food.buff.type, food.buff.amount, 30); // 30 second buffs
            effectsApplied.push(`+${(food.buff.amount * 100).toFixed(0)}% ${food.buff.type}`);
        }
        
        // Show status
        const effectText = effectsApplied.length > 0 ? effectsApplied.join(', ') : 'No effect';
        this.voxelWorld.updateStatus(`${food.name} eaten! ${effectText}`, 'discovery');
        
        return true;
    }
    
    /**
     * Add a buff (stacks with existing buffs)
     */
    addBuff(type, amount, duration) {
        const buff = {
            type: type,
            amount: amount,
            endTime: Date.now() + (duration * 1000),
            duration: duration
        };
        
        this.activeBuffs.push(buff);
        
        console.log(`🌟 Buff added: +${(amount * 100).toFixed(0)}% ${type} for ${duration}s (${this.activeBuffs.length} buffs active)`);
        
        // Apply buff immediately
        this.applyBuffs();
    }
    
    /**
     * Apply all active buffs to player
     */
    applyBuffs() {
        // Calculate total buff amounts
        let speedBonus = 0;
        let staminaRegenBonus = 0;
        let staminaDrainReduction = 0;
        
        for (const buff of this.activeBuffs) {
            if (buff.type === 'speed') {
                speedBonus += buff.amount;
            } else if (buff.type === 'stamina_regen') {
                staminaRegenBonus += buff.amount;
            } else if (buff.type === 'stamina_drain_reduction') {
                staminaDrainReduction += buff.amount;
            }
        }
        
        // Apply to stamina system
        if (this.voxelWorld.staminaSystem) {
            // Speed buff
            if (speedBonus > 0) {
                this.voxelWorld.staminaSystem.normalSpeedMultiplier = 1.0 + speedBonus;
            } else {
                this.voxelWorld.staminaSystem.normalSpeedMultiplier = 1.0;
            }
            
            // Stamina drain reduction
            if (staminaDrainReduction > 0) {
                // Apply reduction to drain rates (multiply by 1.0 - reduction)
                const drainMultiplier = 1.0 - Math.min(staminaDrainReduction, 0.9); // Cap at 90% reduction
                this.voxelWorld.staminaSystem.foodDrainMultiplier = drainMultiplier;
            } else {
                this.voxelWorld.staminaSystem.foodDrainMultiplier = 1.0;
            }
            
            // Stamina regen buff (apply to PlayerCharacter)
            if (this.voxelWorld.playerCharacter) {
                const baseRegen = 10 + (this.voxelWorld.playerCharacter.stats.DEX - 2) * 2;
                this.voxelWorld.playerCharacter.staminaRegen = baseRegen * (1.0 + staminaRegenBonus);
            }
        }
    }
    
    /**
     * Update buffs (call every frame)
     */
    update(deltaTime) {
        const now = Date.now();
        let buffsRemoved = false;
        
        // Remove expired buffs
        this.activeBuffs = this.activeBuffs.filter(buff => {
            if (buff.endTime <= now) {
                console.log(`🌟 Buff expired: ${buff.type}`);
                buffsRemoved = true;
                return false;
            }
            return true;
        });
        
        // Reapply buffs if any were removed
        if (buffsRemoved) {
            this.applyBuffs();
        }
    }
    
    /**
     * Get active buff summary for UI display
     */
    getActiveBuffs() {
        const summary = {};
        
        for (const buff of this.activeBuffs) {
            if (!summary[buff.type]) {
                summary[buff.type] = { count: 0, totalAmount: 0, remainingTime: 0 };
            }
            
            summary[buff.type].count++;
            summary[buff.type].totalAmount += buff.amount;
            summary[buff.type].remainingTime = Math.max(
                summary[buff.type].remainingTime,
                (buff.endTime - Date.now()) / 1000
            );
        }
        
        return summary;
    }
    
    /**
     * Get food info for tooltip
     */
    getFoodInfo(itemType) {
        const baseType = itemType.replace('crafted_', '');
        const food = this.foodData[baseType];
        
        if (!food) return null;
        
        const effects = [];
        
        if (food.healing > 0) {
            const hearts = Math.floor(food.healing / 2);
            const halfHeart = food.healing % 2;
            let healText = '';
            if (hearts > 0) healText += `${hearts}❤️`;
            if (halfHeart > 0) healText += '💔';
            effects.push(`Restores ${healText}`);
        }
        
        if (food.stamina > 0) {
            effects.push(`+${food.stamina} stamina`);
        }
        
        if (food.buff) {
            effects.push(`+${(food.buff.amount * 100).toFixed(0)}% ${food.buff.type} (30s)`);
        }
        
        return {
            name: food.name,
            effects: effects
        };
    }
}
