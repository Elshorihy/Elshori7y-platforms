import React from "react";
export default function StatCard({label,value}:{label:string;value:number|string}){return <div className="stat-card"><div className="stat-card__value">{value}</div><div className="stat-card__label">{label}</div></div>;}
