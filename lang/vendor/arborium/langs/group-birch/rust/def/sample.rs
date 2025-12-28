use std::fmt;

pub trait Greet {
    fn greet(&self) -> String;
}

#[derive(Debug, Clone)]
pub struct Person {
    name: String,
    role: Role,
}

pub enum Role {
    Admin,
    User { permissions: Vec<String> },
}

impl Greet for Person {
    fn greet(&self) -> String {
        format!("Hello, I'm {}!", self.name)
    }
}

impl fmt::Display for Person {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} ({:?})", self.name, self.role)
    }
}

fn main() {
    let alice = Person {
        name: "Alice".into(),
        role: Role::Admin,
    };
    println!("{}", alice.greet());
}
