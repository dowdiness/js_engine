function Hero(name) {
  this.name = name;
  this.hp = 100;
}

Hero.prototype.attack = function(monster) {
  console.log(this.name + " attacks " + monster.name + "!");
  monster.hp = monster.hp - 10;
};

var hero = new Hero("JS-Warrior");
var slime = { name: "Slime", hp: 30 };

hero.attack(slime); // JS-Warrior attacks Slime!
console.log(slime.hp); // 20
